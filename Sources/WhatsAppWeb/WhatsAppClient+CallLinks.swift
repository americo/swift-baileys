import Foundation

extension WhatsAppClient {
	private static let callServiceTimeout: Duration = .seconds(20)

	// MARK: Links

	/// Creates a link anyone can use to come into a call, for as long as the service keeps it.
	public func createCallLink(media: CallLinkMedia) async throws -> CallLink {
		let ack = try await query(
			CallStanzaBuilder.linkCreate(media: media, stanzaID: messageIDGenerator.generate()),
			timeout: Self.callServiceTimeout
		)
		let link = try CallLink.parse(createAck: ack)
		guard link.media == media else {
			throw GroupCallStanzaError.malformed("the link_create ack changed the media")
		}

		return link
	}

	/// What a link says about itself, without joining it.
	public func previewCallLink(_ link: CallLink) async throws -> CallLinkPreview {
		let ack = try await query(
			CallStanzaBuilder.linkQuery(link: link, stanzaID: messageIDGenerator.generate()),
			timeout: Self.callServiceTimeout
		)
		let preview = try CallLinkPreview.parse(queryAck: ack)
		guard preview.link == link else {
			throw GroupCallStanzaError.malformed("the link_query ack names another link")
		}

		return preview
	}

	/// Joins a link's call, starting it if nobody is there yet.
	///
	/// Signaling only, as with `startGroupCall`. Inside, media starts from `groupMediaConfiguration` once
	/// the roster holds this device and a relay, which may be in this answer or in a later `.groupUpdate`.
	/// In the waiting room, that update is also how this device hears it was let in. Until then it keeps
	/// its place with `sendWaitingRoomHeartbeat`.
	public func joinCallLink(_ link: CallLink) async throws -> CallLinkJoin {
		let ack = try await query(
			CallStanzaBuilder.linkJoin(link: link, stanzaID: messageIDGenerator.generate()),
			timeout: Self.callServiceTimeout
		)
		var join = try CallLinkJoin.parse(ack: ack, link: link)

		// An update can overtake the ack, on a path of its own, and be newer than what the ack holds.
		var record = groupCalls[join.callID]
			?? GroupCallRecord(state: GroupCallState(callID: join.callID, callCreator: join.callCreator))
		if let room = join.waitingRoom {
			guard record.applyWaitingRoom(room) != .refused else {
				throw GroupCallStanzaError.malformed("the waiting room in the link_join ack was refused")
			}
		}
		join.waitingRoom = record.waitingRoom

		if let snapshot = join.group {
			let applied = record.state.applyInitialOfferAck(snapshot)
			guard applied == .applied || applied == .relayOnly || applied == .stale else {
				throw GroupCallStanzaError.malformed("the link_join ack's roster was refused")
			}
			record.state.adoptRelayIfMissing(snapshot.relay)
		}
		storeGroupCallRecord(record, for: join.callID)

		let acked = join.group
		join.group = record.state.snapshot
		join.isInWaitingRoom = join.isInWaitingRoom && !(record.state.snapshot.map { isThisDeviceConnected(to: $0) } ?? false)
		if let acked, let current = record.state.snapshot {
			try await keyInitialRosterIfDue(ack: acked, current: current, callID: join.callID)
		}

		return join
	}

	// MARK: Waiting room

	/// Keeps a place in the waiting room, which the service otherwise gives up.
	public func sendWaitingRoomHeartbeat(callID: String, callCreator: String) async throws {
		try await sendNode(CallStanzaBuilder.waitingRoomHeartbeat(
			callID: callID,
			callCreator: callCreator,
			stanzaID: messageIDGenerator.generate()
		))
	}

	/// Sets whether people need letting in. Only those the waiting room calls admins can change it.
	public func setCallApprovalRequired(_ required: Bool, callID: String, callCreator: String) async throws {
		try await waitingRoomRequest(CallStanzaBuilder.waitingRoomToggle(
			callID: callID,
			callCreator: callCreator,
			enabled: required,
			stanzaID: messageIDGenerator.generate()
		))
		groupCalls[callID]?.waitingRoom?.isEnabled = required
	}

	public func admitWaitingUser(_ user: String, callID: String, callCreator: String) async throws {
		try await waitingRoomRequest(CallStanzaBuilder.waitingRoomAdmit(
			callID: callID,
			callCreator: callCreator,
			user: user,
			stanzaID: messageIDGenerator.generate()
		))
	}

	public func denyWaitingUser(_ user: String, callID: String, callCreator: String) async throws {
		try await waitingRoomRequest(CallStanzaBuilder.waitingRoomDeny(
			callID: callID,
			callCreator: callCreator,
			user: user,
			stanzaID: messageIDGenerator.generate()
		))
	}

	private func waitingRoomRequest(_ node: BinaryNode) async throws {
		let ack = try await query(node, timeout: Self.callServiceTimeout)
		try CallLinkStanza.validate(ack)
	}

	/// Commits a `<waiting_room_update>` and tells the app, for a call this device may not have heard the
	/// answer to joining yet. Only the creator or the service can write it.
	func handleWaitingRoomStanza(_ node: BinaryNode, action: BinaryNode, chatID: String, date: Date) {
		let room: CallWaitingRoom
		do {
			room = try CallWaitingRoom.parse(update: action)
		} catch {
			WhatsAppLog.logger.error("call link: unreadable waiting room: \(String(describing: error), privacy: .public)")
			return
		}

		let sender = node.attrs["participant"] ?? chatID
		var record = groupCalls[room.callID]
			?? GroupCallRecord(state: GroupCallState(callID: room.callID, callCreator: room.callCreator))
		guard sender == CallStanzaBuilder.callService
			|| isAuthorizedGroupRosterWriter(sender, record: record, creator: room.callCreator, callID: room.callID) else {
			WhatsAppLog.logger.notice("call link \(room.callID, privacy: .public): waiting room from a sender who may not write it")
			return
		}
		guard record.applyWaitingRoom(room) == .applied else {
			return
		}

		storeGroupCallRecord(record, for: room.callID)
		WhatsAppLog.logger.notice("call link \(room.callID, privacy: .public): waiting room transaction=\(room.transactionID.map(String.init) ?? "-", privacy: .public) enabled=\(room.isEnabled) admin=\(room.isAdmin) waiting=\(room.users.count)")
		eventContinuation.yield(.call([WhatsAppCallEvent(
			chatID: chatID,
			from: room.callCreator,
			isGroup: true,
			id: room.callID,
			date: date,
			isVideo: room.link.media == .video,
			status: .waitingRoom,
			offline: node.attrs["offline"] != nil,
			senderJID: sender,
			waitingRoom: room
		)]))
	}

	// MARK: Screen sharing

	/// Says this device's video has become its screen, or has stopped being it. `to` is the call scope for
	/// a group. The pictures themselves go out as this device's video, and the first must be a keyframe.
	public func sendScreenShareState(
		_ state: CallScreenShareState,
		callID: String,
		to: String,
		callCreator: String
	) async throws {
		try await sendNode(CallStanzaBuilder.screenShare(
			callID: callID,
			to: to,
			callCreator: callCreator,
			stanzaID: messageIDGenerator.generate(),
			state: state
		))
	}
}
