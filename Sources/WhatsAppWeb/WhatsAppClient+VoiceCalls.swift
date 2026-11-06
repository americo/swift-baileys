import Foundation

public enum WhatsAppVoiceCallError: Error, Equatable, Sendable {
	case noDevices
	case unknownCall(String)
	case missingOfferKey
	case undecryptableOffer
	case missingCallKey
	case missingOwnLID
	case peerLIDUnknown(String)
	case missingRelay
	case offerRejected(String)
	/// More members than a call holds, counting this device.
	case groupTooLarge(Int)
	case alreadyInCall
	/// Going back into a call that has ended meanwhile.
	case callOver
	/// Going back into a call was refused, with this status.
	case rejoinRefused(String)
}

/// An outgoing voice call whose `<offer>` was accepted by the server.
public struct WhatsAppOutgoingVoiceCall: Equatable, Sendable {
	public let callID: String
	public let peer: String
	public let callCreator: String
	public let callKey: Data
	/// Devices the offer rang, so the others can stop ringing once one of them answers.
	public let devices: [String]
	/// The server's `<ack class="call" type="offer">`; it carries the relay allocation.
	public let offerAck: BinaryNode
	public let isVideo: Bool

	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.callID == rhs.callID && lhs.peer == rhs.peer && lhs.callCreator == rhs.callCreator
			&& lhs.callKey == rhs.callKey && lhs.devices == rhs.devices && lhs.offerAck == rhs.offerAck
			&& lhs.isVideo == rhs.isVideo
	}
}

/// An incoming voice call whose call key was decrypted from the offer.
public struct WhatsAppIncomingVoiceCall: Equatable, Sendable {
	public let callID: String
	public let callCreator: String
	public let chatID: String
	public let callKey: Data
	public let offer: BinaryNode

	/// Whether the caller asked for video.
	public var isVideo: Bool {
		offer.firstChild(named: "video") != nil
	}

	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.callID == rhs.callID && lhs.callCreator == rhs.callCreator && lhs.chatID == rhs.chatID
			&& lhs.callKey == rhs.callKey && lhs.offer == rhs.offer
	}
}

extension WhatsAppClient {
	// MARK: Outgoing

	/// Places a 1:1 call: generates the call key, encrypts it for every device of `peer` and sends the
	/// `<offer>`, waiting for the server's ack.
	///
	/// This only performs the signaling half of a call. Media (relay, SRTP, audio, video) is separate.
	public func startVoiceCall(to requestedPeer: String, video: Bool = false) async throws -> WhatsAppOutgoingVoiceCall {
		guard let me = authenticationState?.credentials.me else {
			throw WhatsAppClientError.missingAuthenticatedUser
		}
		guard let messageEncryptor else {
			throw WhatsAppClientError.missingMessageEncryptor
		}
		// Media keys derive from LIDs on both sides, so a direct call needs ours and the peer's.
		guard let callCreator = me.lid else {
			throw WhatsAppVoiceCallError.missingOwnLID
		}

		let peer = try await resolvePeerLID(requestedPeer)
		let devices = try await getUSyncDevices([peer], useCache: false, ignoreZeroDevices: false).map(\.jid)
		guard !devices.isEmpty else {
			throw WhatsAppVoiceCallError.noDevices
		}

		_ = try await assertSessions(for: devices, force: false)

		let callKey = try CallKeyMessage.generateCallKey()
		let plaintext = try CallKeyMessage.encode(callKey: callKey, encoder: messageEncoder)
		var deviceKeys = [CallOfferDeviceKey]()
		for device in devices {
			let encrypted = try await messageEncryptor.encryptMessage(jid: device, data: plaintext)
			deviceKeys.append(CallOfferDeviceKey(
				deviceJID: device,
				ciphertext: encrypted.ciphertext,
				encryptionType: encrypted.type
			))
		}

		let deviceIdentity = try deviceIdentityIfNeeded(for: deviceKeys)
		let callID = try Self.generateCallID()
		let stanzaID = try messageIDGenerator.generate()
		let offer = CallStanzaBuilder.offer(
			callID: callID,
			to: peer,
			callCreator: callCreator,
			stanzaID: stanzaID,
			deviceKeys: deviceKeys,
			capability: video ? CallCapability.standardOpusVideoOffer : CallCapability.standardOpusOffer,
			deviceIdentity: deviceIdentity,
			multiDevice: devices.count > 1,
			video: video
		)

		let ack = try await query(offer, timeout: .seconds(20))
		if let error = ack.attrs["error"], !error.isEmpty, error != "0" {
			throw WhatsAppVoiceCallError.offerRejected(error)
		}

		let call = WhatsAppOutgoingVoiceCall(
			callID: callID,
			peer: peer,
			callCreator: callCreator,
			callKey: callKey,
			devices: devices,
			offerAck: ack,
			isVideo: video
		)
		await announceRelay(for: call)
		return call
	}

	// MARK: Incoming

	/// Decrypts the call key of a pending incoming offer. The offer must have been delivered through
	/// the `.call` event with status `.offer`.
	public func prepareIncomingVoiceCall(id callID: String) async throws -> WhatsAppIncomingVoiceCall {
		guard let offerStanza = callOfferNodes[callID],
			  let offer = offerStanza.firstChild(named: "offer") ?? offerStanza.firstChild(named: "offer_notice") else {
			throw WhatsAppVoiceCallError.unknownCall(callID)
		}
		guard let messageDecryptor else {
			throw WhatsAppClientError.missingAuthenticationState
		}

		let creator = offer.attrs["call-creator"] ?? offer.attrs["from"] ?? offerStanza.attrs["from"] ?? ""
		let chatID = offerStanza.attrs["from"] ?? creator
		guard let enc = Self.offerEncNode(in: offer, ownDevices: ownDeviceJIDs) else {
			throw WhatsAppVoiceCallError.missingOfferKey
		}

		let carrier = BinaryNode(tag: "message", attrs: ["from": creator], content: .nodes([enc]))
		guard let message = try await messageDecryptor.decryptIncomingMessage(from: carrier) else {
			throw WhatsAppVoiceCallError.undecryptableOffer
		}
		guard let callKey = CallKeyMessage.callKey(from: message) else {
			throw WhatsAppVoiceCallError.missingCallKey
		}

		return WhatsAppIncomingVoiceCall(
			callID: callID,
			callCreator: creator,
			chatID: chatID,
			callKey: callKey,
			offer: offer
		)
	}

	/// Sends `<preaccept>` so the caller hears ringing while the user decides.
	public func preacceptVoiceCall(_ call: WhatsAppIncomingVoiceCall) async throws {
		try await sendNode(CallStanzaBuilder.preaccept(
			callID: call.callID,
			to: call.chatID,
			callCreator: call.callCreator,
			stanzaID: messageIDGenerator.generate(),
			video: call.isVideo
		))
	}

	/// Sends `<accept>` for an incoming call. `relayTransportEndpoint` and `routingToken` come from
	/// the relay selected for the call; pass `nil` until the media layer provides them.
	public func acceptVoiceCall(
		_ call: WhatsAppIncomingVoiceCall,
		relayTransportEndpoint: Data? = nil,
		routingToken: Data? = nil
	) async throws {
		try await sendNode(CallStanzaBuilder.accept(
			callID: call.callID,
			to: call.chatID,
			callCreator: call.callCreator,
			stanzaID: messageIDGenerator.generate(),
			relayTransportEndpoint: relayTransportEndpoint,
			routingToken: routingToken,
			video: call.isVideo,
			peerMetadata: call.isVideo ? CallPeerMetadata(offer: call.offer) : nil
		))
	}

	/// Rejects a ringing call without decrypting its offer.
	///
	/// Without a reason this declines the call on every device of this account. `busy` is a statement
	/// about this device alone, and the caller's other targets keep ringing.
	public func rejectIncomingCall(
		id callID: String,
		callCreator: String,
		to: String,
		reason: String? = nil
	) async throws {
		try await sendNode(CallStanzaBuilder.reject(
			callID: callID,
			to: to,
			callCreator: callCreator,
			stanzaID: messageIDGenerator.generate(),
			reason: reason
		))
		if reason == nil {
			callOfferNodes.removeValue(forKey: callID)
		}
	}

	/// Rejects an incoming call with an optional reason such as `busy`.
	public func rejectVoiceCall(_ call: WhatsAppIncomingVoiceCall, reason: String? = nil) async throws {
		try await sendNode(CallStanzaBuilder.reject(
			callID: call.callID,
			to: call.chatID,
			callCreator: call.callCreator,
			stanzaID: messageIDGenerator.generate(),
			reason: reason
		))
		callOfferNodes.removeValue(forKey: call.callID)
	}

	/// Tells the other devices of the callee to stop ringing and answers the `<accept>` with
	/// `<transport>`, as the official client does when it is the caller.
	public func announceAnswer(of call: WhatsAppOutgoingVoiceCall, answeredBy sender: String) async {
		for device in call.devices where !Self.isSameDevice(device, sender) {
			try? await sendNode(CallStanzaBuilder.terminate(
				callID: call.callID,
				to: device,
				callCreator: call.callCreator,
				stanzaID: messageIDGenerator.generate(),
				reason: CallStanzaBuilder.terminateReasonAcceptedElsewhere
			))
		}

		guard let stanzaID = try? messageIDGenerator.generate() else {
			return
		}

		try? await sendNode(CallStanzaBuilder.transport(
			callID: call.callID,
			to: sender,
			callCreator: call.callCreator,
			stanzaID: stanzaID
		))
	}

	/// Sends a mid-call `<video>` stanza, which turns our direction on or off or negotiates an upgrade.
	/// `to` is the device the call is with.
	public func sendVideoState(
		_ state: CallVideoState,
		callID: String,
		to: String,
		callCreator: String,
		transactionID: UInt32? = nil
	) async throws {
		let announcesDecoder = state != .stopped && state != .upgradeReject && state != .upgradeCancel
			&& state != .upgradeCancelByTimeout
		try await sendNode(CallStanzaBuilder.videoState(
			callID: callID,
			to: to,
			callCreator: callCreator,
			stanzaID: messageIDGenerator.generate(),
			state: state,
			decoders: announcesDecoder ? CallStanzaBuilder.videoDecoders : nil,
			// Official clients state a rotation on every `<video>` in a group, where they are numbered.
			deviceOrientation: announcesDecoder || transactionID != nil ? CallStanzaBuilder.uprightOrientation : nil,
			transactionID: transactionID
		))
	}

	/// Ends a call in progress, or cancels an outgoing call that has not been answered.
	public func endVoiceCall(id callID: String, peer: String, callCreator: String, reason: String? = nil) async throws {
		try await sendNode(CallStanzaBuilder.terminate(
			callID: callID,
			to: peer,
			callCreator: callCreator,
			stanzaID: messageIDGenerator.generate(),
			reason: reason
		))
		callOfferNodes.removeValue(forKey: callID)
	}

	// MARK: Media session

	/// Configuration for the media session of an outgoing call, taken from the offer ack.
	///
	/// `sender` is the device that answered: the peer encrypts under its own device id, so receive
	/// keys derive from it, not from the bare contact the offer rang.
	public func mediaConfiguration(
		for call: WhatsAppOutgoingVoiceCall,
		answeredBy sender: String
	) throws -> CallSession.Configuration {
		guard let relay = CallRelayData.parse(fromAck: call.offerAck) else {
			throw WhatsAppVoiceCallError.missingRelay
		}

		return CallSession.Configuration(
			callID: call.callID,
			selfParticipantID: call.callCreator,
			peerParticipantID: Self.answeringParticipantID(peer: call.peer, sender: sender),
			callKey: call.callKey,
			relay: relay
		)
	}

	/// Configuration for the media session of an incoming call, taken from the offer's relay block.
	public func mediaConfiguration(for call: WhatsAppIncomingVoiceCall) throws -> CallSession.Configuration {
		guard let me = authenticationState?.credentials.me, let lid = me.lid else {
			throw WhatsAppVoiceCallError.missingOwnLID
		}
		// The caller keys its receive path to the device in our `<accept>`, so ours must name it.
		let selfID = Self.deviceQualifiedLID(lid, deviceFrom: me.id)
		guard let relay = CallRelayData.parse(fromAck: call.offer) else {
			throw WhatsAppVoiceCallError.missingRelay
		}

		return CallSession.Configuration(
			callID: call.callID,
			selfParticipantID: selfID,
			peerParticipantID: call.callCreator,
			callKey: call.callKey,
			relay: relay
		)
	}

	// MARK: Helpers

	/// Announces the relay this caller dials. Best effort: the call proceeds without it.
	private func announceRelay(for call: WhatsAppOutgoingVoiceCall) async {
		guard let endpoint = CallRelayData.parse(fromAck: call.offerAck)?.mediaEndpoint(),
			  let address = endpoint.ipv4Bytes,
			  let stanzaID = try? messageIDGenerator.generate() else {
			return
		}

		try? await sendNode(CallStanzaBuilder.relayLatency(
			callID: call.callID,
			to: call.peer,
			callCreator: call.callCreator,
			stanzaID: stanzaID,
			latencyMs: endpoint.clientToRelayRTTMs ?? 40,
			relayName: endpoint.relayName,
			relayAddress: address,
			devices: Self.ackDevices(in: call.offerAck)
		))
	}

	/// The `<device jid>` entries of an offer ack, outside its relay block.
	static func ackDevices(in node: BinaryNode) -> [String] {
		guard case let .nodes(children)? = node.content else {
			return []
		}

		var devices = [String]()
		for child in children where child.tag != "relay" {
			let found = child.tag == "device" ? [child.attrs["jid"]].compactMap { $0 } : ackDevices(in: child)
			for device in found where !devices.contains(device) {
				devices.append(device)
			}
		}

		return devices
	}

	/// Participant id of the device that answered. It may answer in the phone-number namespace, in
	/// which case its device number moves onto the peer's LID.
	public static func answeringParticipantID(peer: String, sender: String) -> String {
		if sender.hasSuffix("@lid") {
			return sender
		}

		let device = sender.split(separator: "@").first?.split(separator: ":").dropFirst().first.map(String.init) ?? "0"
		return "\(userPart(of: peer)):\(device)@lid"
	}

	static func isSameDevice(_ lhs: String, _ rhs: String) -> Bool {
		func device(_ jid: String) -> String {
			jid.split(separator: "@").first?.split(separator: ":").dropFirst().first.map(String.init) ?? "0"
		}

		return userPart(of: lhs) == userPart(of: rhs) && device(lhs) == device(rhs)
	}

	/// A phone-number JID mapped to its LID, or the JID unchanged when it already is one.
	func resolvePeerLID(_ peer: String) async throws -> String {
		if peer.hasSuffix("@lid") {
			return peer
		}
		guard let keys = authenticationState?.keys,
			  let lid = try await LIDMappingStore.lid(for: peer, in: keys) else {
			throw WhatsAppVoiceCallError.peerLIDUnknown(peer)
		}

		return lid.contains("@") ? lid : "\(lid)@lid"
	}

	var ownDeviceJIDs: [String] {
		guard let me = authenticationState?.credentials.me else {
			return []
		}

		var devices = [me.id]
		if let lid = me.lid {
			devices.append(lid)
			devices.append(Self.deviceQualifiedLID(lid, deviceFrom: me.id))
		}

		return devices
	}

	/// Finds the `<enc>` addressed to this device: a direct child, or the one under the
	/// `<destination><to jid=…>` entry naming this device. Every device of the account can be listed
	/// and each key only decrypts on its own device, so another device's entry is never a fallback.
	static func offerEncNode(in offer: BinaryNode, ownDevices: [String]) -> BinaryNode? {
		if let direct = offer.firstChild(named: "enc") {
			return direct
		}

		let destinations = offer.firstChild(named: "destination")?.children(named: "to") ?? []
		let own = destinations.first { to in
			guard let jid = to.attrs["jid"] else {
				return false
			}

			return ownDevices.contains { isSameDevice($0, jid) }
		}
		return own?.firstChild(named: "enc")
	}

	/// `lid` with the device number of `id`, when `lid` does not already carry one.
	static func deviceQualifiedLID(_ lid: String, deviceFrom id: String) -> String {
		let user = lid.split(separator: "@").first.map(String.init) ?? lid
		guard !user.contains(":"),
			  let device = id.split(separator: "@").first?.split(separator: ":").dropFirst().first else {
			return lid
		}

		return "\(user):\(device)@lid"
	}

	static func userPart(of jid: String) -> String {
		let beforeAt = jid.split(separator: "@", maxSplits: 1).first.map(String.init) ?? jid
		return beforeAt.split(separator: ":", maxSplits: 1).first.map(String.init) ?? beforeAt
	}

	func deviceIdentityIfNeeded(for keys: [CallOfferDeviceKey]) throws -> Data? {
		guard keys.contains(where: { $0.encryptionType == "pkmsg" }),
			  let account = authenticationState?.credentials.account else {
			return nil
		}

		return try Self.encodedSignedDeviceIdentity(account)
	}

	static func generateCallID() throws -> String {
		var bytes = [UInt8](repeating: 0, count: 16)
		let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
		guard status == errSecSuccess else {
			throw CallKeyMessageError.randomGenerationFailed(status)
		}

		return bytes.map { String(format: "%02X", $0) }.joined()
	}
}
