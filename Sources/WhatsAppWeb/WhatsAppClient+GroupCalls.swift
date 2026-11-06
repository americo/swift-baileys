import Foundation

/// A group call whose `<offer>` the server accepted.
public struct WhatsAppOutgoingGroupCall: Equatable, Sendable {
	public let callID: String
	public let callCreator: String
	public let groupJID: String?
	public let isVideo: Bool
	/// The roster as of the ack, or newer if an update overtook it.
	public let update: GroupCallUpdate
}

/// What a client keeps per group call, ahead of whichever media session ends up using it: a roster or
/// a key can reach this device before the offer or the session they belong to.
struct GroupCallRecord: Sendable {
	static let maxRetainedEpochs = 8

	var state: GroupCallState
	var epochs = [GroupCallEpoch]()
	/// The transaction a key is being generated for. An update and the ack it overtook can both ask, and
	/// two different keys under one transaction would be refused by everyone who got the second.
	var keyInFlight: UInt32?
	let createdAt = Date()

	mutating func retain(_ epoch: GroupCallEpoch) {
		guard !epochs.contains(where: { $0.transactionID == epoch.transactionID }) else {
			return
		}

		epochs.append(epoch)
		if epochs.count > Self.maxRetainedEpochs {
			epochs.removeFirst()
		}
	}
}

extension WhatsAppClient {
	/// A record for each call is created on demand from unauthenticated-until-checked stanzas, so their
	/// number stays bounded even if some call never ends in a way this device hears about.
	private static let maxGroupCallRecords = 16
	/// How long a key for a call with no known roster is kept.
	private static let unclaimedKeyLifetime: Duration = .seconds(60)

	// MARK: Outgoing

	/// Rings the current members of a group. The call needs at least one other member, and everyone in
	/// it must fit in a call.
	///
	/// Signaling only, as with `startVoiceCall`. The offer carries no key: the service asks one device to
	/// generate it with `rekey`, which is usually this one, on the ack or the first update.
	public func startGroupCall(groupJID: String, video: Bool = false) async throws -> WhatsAppOutgoingGroupCall {
		guard let me = authenticationState?.credentials.me else {
			throw WhatsAppClientError.missingAuthenticatedUser
		}
		guard let lid = me.lid else {
			throw WhatsAppVoiceCallError.missingOwnLID
		}

		let ownDevice = Self.deviceQualifiedLID(lid, deviceFrom: me.id)
		let metadata = try await groupMetadata(groupJID)
		let targets = try await groupCallTargets(metadata, ownLID: lid, ownPhone: me.id)
		guard !targets.isEmpty else {
			throw WhatsAppVoiceCallError.noDevices
		}
		guard targets.count <= GroupCallLimits.maxRemoteParticipants else {
			throw WhatsAppVoiceCallError.groupTooLarge(targets.count + 1)
		}

		let devices = try await getUSyncDevices(targets, useCache: true, ignoreZeroDevices: false)
			.map(\.jid)
			.filter { !CallJID.isHosted($0) }
		var participants = [GroupCallParticipant(
			jid: CallJID.user(ownDevice),
			devices: [GroupCallDevice(
				jid: ownDevice,
				capabilityVersion: 1,
				capability: video ? CallCapability.standardOpusVideoOffer : CallCapability.standardOpusOffer
			)]
		)]
		for target in targets {
			let own = devices.filter { CallJID.isSameUser($0, target) }
			if !own.isEmpty {
				participants.append(GroupCallParticipant(jid: target, devices: own.map { GroupCallDevice(jid: $0) }))
			}
		}
		guard participants.count > 1 else {
			throw WhatsAppVoiceCallError.noDevices
		}

		let callID = try Self.generateCallID()
		let offer = try CallStanzaBuilder.groupOffer(
			callID: callID,
			callCreator: ownDevice,
			stanzaID: messageIDGenerator.generate(),
			groupJID: groupJID,
			participants: participants,
			video: video
		)
		// Registered first: an update can overtake the ack, on a path of its own.
		storeGroupCallRecord(GroupCallRecord(state: GroupCallState(callID: callID, callCreator: ownDevice)), for: callID)

		do {
			let ack = try await query(offer, timeout: .seconds(20))
			guard let snapshot = try GroupCallUpdate.parse(offerAck: ack) else {
				throw GroupCallStanzaError.malformed("the offer ack has no group snapshot")
			}
			guard snapshot.callID == callID, snapshot.callCreator == ownDevice, snapshot.isVideo == video else {
				throw GroupCallStanzaError.malformed("the offer ack does not match the offer")
			}

			var state = groupCalls[callID]?.state ?? GroupCallState(callID: callID, callCreator: ownDevice)
			let applied = state.applyInitialOfferAck(snapshot)
			guard applied == .applied || applied == .relayOnly || applied == .stale else {
				throw GroupCallStanzaError.malformed("the offer ack's roster was refused")
			}

			state.adoptRelayIfMissing(snapshot.relay)
			groupCalls[callID]?.state = state
			guard let update = state.snapshot, update.isVideo == video else {
				throw GroupCallStanzaError.malformed("the offer ack has no usable roster")
			}
			guard update.relay != nil else {
				throw WhatsAppVoiceCallError.missingRelay
			}

			if let keyed = epochRoster(ack: snapshot, current: update, retained: groupCalls[callID]?.epochs.last?.transactionID),
			   groupCalls[callID]?.keyInFlight != keyed.transactionID {
				groupCalls[callID]?.keyInFlight = keyed.transactionID
				let key = try await fanOutGroupEpoch(keyed)
				retainGroupEpoch(GroupCallEpoch(transactionID: keyed.transactionID, key: key), for: callID)
			}

			return WhatsAppOutgoingGroupCall(
				callID: callID,
				callCreator: ownDevice,
				groupJID: groupJID,
				isVideo: video,
				update: update
			)
		} catch {
			forgetGroupCall(id: callID)
			try? await sendNode(CallStanzaBuilder.terminate(
				callID: callID,
				to: groupCallScope(callID: callID),
				callCreator: ownDevice,
				stanzaID: messageIDGenerator.generate()
			))
			throw error
		}
	}

	/// The members to ring, in the LID namespace media keys need. Someone with no known LID cannot be
	/// keyed for, and is left out rather than failing the call for everyone else.
	private func groupCallTargets(_ metadata: GroupMetadata, ownLID: String, ownPhone: String) async throws -> [String] {
		var targets = [String]()
		for participant in metadata.participants {
			let resolved: String?
			if let lid = participant.lid {
				resolved = lid
			} else if let found = try? await resolvePeerLID(participant.id) {
				resolved = found
			} else {
				resolved = nil
			}

			guard let resolved else {
				WhatsAppLog.logger.notice("group call: no LID for a member, leaving them out")
				continue
			}

			let user = CallJID.user(resolved)
			let isSelf = CallJID.isSameUser(user, ownLID)
				|| CallJID.isSameUser(participant.id, ownLID)
				|| CallJID.isSameUser(participant.id, ownPhone)
			if !isSelf, !targets.contains(user) {
				targets.append(user)
			}
		}

		return targets
	}

	/// The roster a key for this ack should go out under, if one is due.
	///
	/// A zero transaction cannot name a key's epoch. The request then waits, parked by the state, for the
	/// first ordered roster. An ordered roster that arrived first makes the ack stale, so nothing is parked
	/// and this comparison is all that answers it.
	private func epochRoster(ack: GroupCallUpdate, current: GroupCallUpdate, retained: UInt32?) -> GroupCallUpdate? {
		guard ack.isRekeyRequested, current.transactionID != 0 else {
			return nil
		}

		let requested = ack.transactionID == 0 ? current.transactionID : ack.transactionID
		return retained.map { $0 < requested } ?? true ? current : nil
	}

	// MARK: Incoming

	/// Answers a ringing group call: `<preaccept>` and `<accept>` to the call scope.
	///
	/// Returns the media configuration when this device already has what it takes. `nil` means an
	/// invitation with neither a key nor a relay, where the answer itself is what brings them: wait for a
	/// `.groupUpdate` with a relay, and then ask `groupMediaConfiguration`.
	public func answerGroupCall(id callID: String) async throws -> CallSession.Configuration? {
		guard let stanza = callOfferNodes[callID], let offer = stanza.firstChild(named: "offer") else {
			throw WhatsAppVoiceCallError.unknownCall(callID)
		}

		let creator = offer.attrs["call-creator"] ?? ""
		let isVideo = offer.firstChild(named: "video") != nil
		let scope = groupCallScope(callID: callID)
		try await sendNode(CallStanzaBuilder.preaccept(
			callID: callID,
			to: scope,
			callCreator: creator,
			stanzaID: messageIDGenerator.generate(),
			video: isVideo
		))

		let configuration: CallSession.Configuration?
		if groupCalls[callID]?.state.snapshot?.relay != nil {
			configuration = try groupMediaConfiguration(callID: callID)
		} else {
			configuration = try await directConfiguration(ofGroupOffer: offer, stanza: stanza, callID: callID, creator: creator)
		}

		try await sendNode(CallStanzaBuilder.accept(
			callID: callID,
			to: scope,
			callCreator: creator,
			stanzaID: messageIDGenerator.generate(),
			video: isVideo,
			peerMetadata: isVideo ? CallPeerMetadata(offer: offer) : nil
		))
		return configuration
	}

	/// A group offer that carries a call key and relay starts like a 1:1 call with whoever invited this
	/// device, and becomes a group call when the first roster with a relay arrives.
	private func directConfiguration(
		ofGroupOffer offer: BinaryNode,
		stanza: BinaryNode,
		callID: String,
		creator: String
	) async throws -> CallSession.Configuration? {
		guard let enc = Self.offerEncNode(in: offer, ownDevices: ownDeviceJIDs),
			  let relay = CallRelayData.parse(fromAck: stanza) else {
			return nil
		}
		guard let me = authenticationState?.credentials.me, let lid = me.lid else {
			throw WhatsAppVoiceCallError.missingOwnLID
		}
		guard let messageDecryptor else {
			throw WhatsAppClientError.missingAuthenticationState
		}

		let sender = Self.groupCallSender(of: stanza, creator: creator)
		let carrier = BinaryNode(tag: "message", attrs: ["from": sender], content: .nodes([enc]))
		guard let message = try await messageDecryptor.decryptIncomingMessage(from: carrier) else {
			throw WhatsAppVoiceCallError.undecryptableOffer
		}
		guard let callKey = CallKeyMessage.callKey(from: message) else {
			throw WhatsAppVoiceCallError.missingCallKey
		}

		return CallSession.Configuration(
			callID: callID,
			selfParticipantID: Self.deviceQualifiedLID(lid, deviceFrom: me.id),
			peerParticipantID: sender,
			callKey: callKey,
			relay: relay
		)
	}

	// MARK: Media session

	/// Media configuration of a call from its current roster, which must hold this device and a relay.
	/// Its media waits for a key, which comes by `.groupEpoch`.
	public func groupMediaConfiguration(callID: String) throws -> CallSession.Configuration {
		guard let me = authenticationState?.credentials.me, let lid = me.lid else {
			throw WhatsAppVoiceCallError.missingOwnLID
		}
		guard let update = groupCalls[callID]?.state.snapshot else {
			throw WhatsAppVoiceCallError.unknownCall(callID)
		}
		guard let relay = update.relay?.forGroupMedia else {
			throw WhatsAppVoiceCallError.missingRelay
		}
		guard let device = Self.localRosterDevice(in: update, ownLID: Self.deviceQualifiedLID(lid, deviceFrom: me.id), ownPhone: me.id) else {
			throw CallGroupMediaError.localParticipantRemoved
		}

		return CallSession.Configuration(
			callID: callID,
			selfParticipantID: device.jid,
			peerParticipantID: device.jid,
			callKey: Data(count: CallMediaCrypto.callKeyLength),
			relay: relay,
			groupUpdate: update
		)
	}

	/// The newest committed roster of a call.
	public func groupCallSnapshot(id callID: String) -> GroupCallUpdate? {
		groupCalls[callID]?.state.snapshot
	}

	/// Keys that reached this device for a call, oldest first, for a session that starts after them.
	public func retainedGroupEpochs(id callID: String) -> [GroupCallEpoch] {
		groupCalls[callID]?.epochs ?? []
	}

	/// Drops what is held about a call, the media keys included.
	public func forgetGroupCall(id callID: String) {
		groupCalls.removeValue(forKey: callID)
	}

	/// The roster without this account, whose other devices are not someone to show as in the call.
	public func remoteGroupParticipants(in update: GroupCallUpdate) -> [GroupCallParticipant] {
		guard let me = authenticationState?.credentials.me else {
			return update.participants
		}

		return update.participants.filter { participant in
			let identities = [participant.jid, participant.phoneJID].compactMap { $0 }
			return !identities.contains { identity in
				CallJID.isSameUser(identity, me.id) || me.lid.map { CallJID.isSameUser(identity, $0) } == true
			}
		}
	}

	static func localRosterDevice(in update: GroupCallUpdate, ownLID: String, ownPhone: String) -> GroupCallDevice? {
		update.localDevice(matching: ownLID) ?? update.localDevice(matching: ownPhone)
	}

	// MARK: Signaling

	/// Leaves a group call. The others carry on.
	public func leaveGroupCall(id callID: String, callCreator: String) async throws {
		try await sendNode(CallStanzaBuilder.terminate(
			callID: callID,
			to: groupCallScope(callID: callID),
			callCreator: callCreator,
			stanzaID: messageIDGenerator.generate()
		))
		callOfferNodes.removeValue(forKey: callID)
		forgetGroupCall(id: callID)
	}

	/// Announces this device's microphone, so the others can show it. `to` is the call scope for a group.
	public func sendMuteState(_ muted: Bool, callID: String, to: String, callCreator: String) async throws {
		try await sendNode(CallStanzaBuilder.mute(
			callID: callID,
			to: to,
			callCreator: callCreator,
			stanzaID: messageIDGenerator.generate(),
			muted: muted
		))
	}

	// MARK: Stanzas

	/// Commits a `<group_update>` and tells the app. Only the creator or the call service may write the
	/// roster. Anyone else's is dropped, however well formed.
	func handleGroupUpdateStanza(_ node: BinaryNode, action: BinaryNode, chatID: String, date: Date) async {
		let update: GroupCallUpdate
		do {
			update = try GroupCallUpdate.parse(groupUpdate: action)
		} catch {
			WhatsAppLog.logger.error("group call: unreadable update: \(String(describing: error), privacy: .public)")
			return
		}

		let sender = node.attrs["participant"] ?? chatID
		var record = groupCalls[update.callID]
			?? GroupCallRecord(state: GroupCallState(callID: update.callID, callCreator: update.callCreator))
		guard isAuthorizedGroupRosterWriter(sender, record: record, creator: update.callCreator, callID: update.callID) else {
			WhatsAppLog.logger.notice("group call \(update.callID, privacy: .public): roster from a sender who may not write it")
			return
		}

		let applied = record.state.apply(update)
		let isFresh = applied == .applied
		let owesKey = isFresh ? record.state.takeOwedRekey() : false
		guard isFresh || applied == .relayOnly, let committed = record.state.snapshot else {
			if applied == .invalid || applied == .identityMismatch {
				WhatsAppLog.logger.notice("group call \(update.callID, privacy: .public): roster refused (\(String(describing: applied), privacy: .public))")
			}
			return
		}

		storeGroupCallRecord(record, for: update.callID)
		eventContinuation.yield(.call([WhatsAppCallEvent(
			chatID: chatID,
			from: update.callCreator,
			isGroup: true,
			groupJID: committed.groupJID,
			id: update.callID,
			date: date,
			isVideo: committed.isVideo,
			status: .groupUpdate,
			offline: node.attrs["offline"] != nil,
			senderJID: sender,
			groupUpdate: committed
		)]))

		// Signal sessions may need the network, and the stanza loop cannot wait on what it delivers.
		if isFresh, update.isRekeyRequested || owesKey, record.keyInFlight != committed.transactionID {
			groupCalls[update.callID]?.keyInFlight = committed.transactionID
			Task { [weak self] in
				await self?.distributeGroupEpoch(for: committed, chatID: chatID, date: date)
			}
		}
	}

	/// Decrypts an `<enc_rekey>` and hands its key to the app.
	func handleGroupEpochStanza(_ node: BinaryNode, action: BinaryNode, chatID: String, date: Date) async {
		guard let callID = action.attrs["call-id"],
			  let creator = action.attrs["call-creator"],
			  let transaction = action.attrs["transaction-id"].flatMap(UInt32.init),
			  transaction != 0,
			  action.firstChild(named: "encopt")?.attrs["keygen"] == "2",
			  let enc = action.firstChild(named: "enc"), enc.attrs["v"] == "2" else {
			WhatsAppLog.logger.notice("group call: unreadable enc_rekey")
			return
		}

		let sender = Self.groupCallSender(of: node, creator: creator)
		if let snapshot = groupCalls[callID]?.state.snapshot,
		   !CallJID.isSameUser(sender, creator),
		   !snapshot.participants.contains(where: { participant in
			   CallJID.isSameUser(sender, participant.jid) || participant.phoneJID.map { CallJID.isSameUser(sender, $0) } == true
		   }) {
			WhatsAppLog.logger.notice("group call \(callID, privacy: .public): key from someone outside the roster")
			return
		}
		guard let messageDecryptor else {
			return
		}

		do {
			let carrier = BinaryNode(tag: "message", attrs: ["from": sender], content: .nodes([enc]))
			guard let message = try await messageDecryptor.decryptIncomingMessage(from: carrier),
				  let key = CallKeyMessage.callKey(from: message), key.count == CallMediaCrypto.callKeyLength else {
				WhatsAppLog.logger.notice("group call \(callID, privacy: .public): enc_rekey carried no key")
				return
			}

			let epoch = GroupCallEpoch(transactionID: transaction, key: key)
			retainGroupEpoch(epoch, for: callID, creator: creator)
			yieldGroupEpoch(epoch, callID: callID, creator: creator, chatID: chatID, date: date, sender: sender)
		} catch {
			WhatsAppLog.logger.error("group call \(callID, privacy: .public): enc_rekey failed: \(String(describing: error), privacy: .public)")
		}
	}

	/// Whether a call's sender may end it for everyone or write its roster: the creator, by either of the
	/// creator's identities, the service, or another device of this account.
	func isAuthorizedGroupRosterWriter(_ sender: String, record: GroupCallRecord?, creator: String, callID: String) -> Bool {
		// A stanza that names no participant comes from the service itself: from the call, or its group.
		if sender == groupCallScope(callID: callID) || sender.hasSuffix("@\(JIDServer.group.rawValue)")
			|| CallJID.isSameUser(sender, creator) {
			return true
		}
		if let me = authenticationState?.credentials.me,
		   CallJID.isSameUser(sender, me.id) || me.lid.map({ CallJID.isSameUser(sender, $0) }) == true {
			return true
		}

		return record?.state.snapshot?.participants.contains { participant in
			CallJID.isSameUser(participant.jid, creator) && participant.phoneJID.map { CallJID.isSameUser(sender, $0) } == true
		} ?? false
	}

	/// Who sent a call stanza. Group signaling arrives from the call service, naming them as `participant`.
	static func groupCallSender(of node: BinaryNode, creator: String) -> String {
		if let participant = node.attrs["participant"] {
			return participant
		}
		if let from = node.attrs["from"], !from.hasSuffix("@\(JIDServer.call.rawValue)") {
			return from
		}

		return creator
	}

	// MARK: Keys

	/// Generates and distributes a key, then gives it to this device's own media.
	private func distributeGroupEpoch(for update: GroupCallUpdate, chatID: String, date: Date) async {
		guard groupCalls[update.callID] != nil else {
			return
		}

		do {
			let key = try await fanOutGroupEpoch(update)
			guard groupCalls[update.callID] != nil else {
				return
			}

			let epoch = GroupCallEpoch(transactionID: update.transactionID, key: key)
			retainGroupEpoch(epoch, for: update.callID)
			yieldGroupEpoch(epoch, callID: update.callID, creator: update.callCreator, chatID: chatID, date: date, sender: nil)
		} catch {
			// The roster moved on and asked for a key nobody now has, so media cannot resume.
			WhatsAppLog.logger.error("group call \(update.callID, privacy: .public): key distribution failed: \(String(describing: error), privacy: .public)")
			try? await leaveGroupCall(id: update.callID, callCreator: update.callCreator)
			eventContinuation.yield(.call([WhatsAppCallEvent(
				chatID: chatID,
				from: update.callCreator,
				isGroup: true,
				id: update.callID,
				date: date,
				status: .terminate,
				offline: false,
				reason: "rekey_failed"
			)]))
		}
	}

	/// One shared key, encrypted independently for each connected remote device holding a media session
	/// and sent to each directly. This device installs it only after this returns.
	///
	/// A device that cannot be encrypted for is left out and logged. It stays deaf, which beats ending the
	/// call for everyone over one companion with a broken session. A send that fails does end it, because
	/// then nobody can tell who holds the key.
	func fanOutGroupEpoch(_ update: GroupCallUpdate) async throws -> Data {
		guard let me = authenticationState?.credentials.me else {
			throw WhatsAppClientError.missingAuthenticatedUser
		}
		guard let messageEncryptor else {
			throw WhatsAppClientError.missingMessageEncryptor
		}

		var seen = Set<String>()
		let recipients = update.participants.filter(\.isConnected).flatMap(\.devices).compactMap { device -> String? in
			guard device.pid != nil,
				  !Self.isSameDevice(device.jid, me.id),
				  me.lid.map({ !Self.isSameDevice(device.jid, Self.deviceQualifiedLID($0, deviceFrom: me.id)) }) ?? true,
				  seen.insert(device.jid).inserted else {
				return nil
			}

			return device.jid
		}

		let key = try CallKeyMessage.generateCallKey()
		guard !recipients.isEmpty else {
			return key
		}

		_ = try await assertSessions(for: recipients, force: false)
		let plaintext = try CallKeyMessage.encode(callKey: key, encoder: messageEncoder)
		var deviceKeys = [CallOfferDeviceKey]()
		for recipient in recipients {
			do {
				let encrypted = try await messageEncryptor.encryptMessage(jid: recipient, data: plaintext)
				deviceKeys.append(CallOfferDeviceKey(
					deviceJID: recipient,
					ciphertext: encrypted.ciphertext,
					encryptionType: encrypted.type
				))
			} catch {
				WhatsAppLog.logger.error("group call \(update.callID, privacy: .public): cannot key \(recipient, privacy: .public): \(String(describing: error), privacy: .public)")
			}
		}
		guard !deviceKeys.isEmpty else {
			throw WhatsAppVoiceCallError.noDevices
		}

		let identity = try deviceIdentityIfNeeded(for: deviceKeys)
		for deviceKey in deviceKeys {
			try await sendNode(CallStanzaBuilder.groupEncRekey(
				callID: update.callID,
				callCreator: update.callCreator,
				stanzaID: messageIDGenerator.generate(),
				transactionID: update.transactionID,
				deviceKey: deviceKey,
				deviceIdentity: deviceKey.encryptionType == "pkmsg" ? identity : nil
			))
		}

		return key
	}

	private func yieldGroupEpoch(
		_ epoch: GroupCallEpoch,
		callID: String,
		creator: String,
		chatID: String,
		date: Date,
		sender: String?
	) {
		eventContinuation.yield(.call([WhatsAppCallEvent(
			chatID: chatID,
			from: creator,
			isGroup: true,
			id: callID,
			date: date,
			status: .groupEpoch,
			offline: false,
			senderJID: sender,
			groupEpoch: epoch
		)]))
	}

	private func retainGroupEpoch(_ epoch: GroupCallEpoch, for callID: String, creator: String? = nil) {
		var record = groupCalls[callID]
		if record == nil, let creator {
			record = GroupCallRecord(state: GroupCallState(callID: callID, callCreator: creator))
			// A key can beat its offer, and is held for it. One that arrives after its call was forgotten,
			// or for a call that never shows up, must not stay in memory.
			Task { [weak self] in
				try? await Task.sleep(for: Self.unclaimedKeyLifetime)
				await self?.forgetGroupCallIfUnclaimed(id: callID)
			}
		}
		guard var record else {
			return
		}

		record.retain(epoch)
		storeGroupCallRecord(record, for: callID)
	}

	private func forgetGroupCallIfUnclaimed(id callID: String) {
		if groupCalls[callID]?.state.snapshot == nil {
			forgetGroupCall(id: callID)
		}
	}

	func storeGroupCallRecord(_ record: GroupCallRecord, for callID: String) {
		groupCalls[callID] = record
		while groupCalls.count > Self.maxGroupCallRecords,
			  let oldest = groupCalls.min(by: { $0.value.createdAt < $1.value.createdAt })?.key {
			groupCalls.removeValue(forKey: oldest)
		}
	}
}
