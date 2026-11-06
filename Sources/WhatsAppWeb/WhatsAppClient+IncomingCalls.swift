import Foundation

extension WhatsAppClient {
	func handleCallNode(_ node: BinaryNode) async -> Bool {
		guard node.tag == "call" else {
			return false
		}
		if let from = node.attrs["from"],
		   from != "@s.whatsapp.net",
		   configuration.shouldIgnoreJID(from) == true {
			if let ack = StanzaAck.build(for: node) {
				try? await sendNode(ack)
			}
			return true
		}

		// Every call stanza, since a hang-up that goes unnoticed leaves nothing else to go on.
		let actions = node.allChildren.map { child in
			let attrs = child.attrs.map { "\($0.0)=\($0.1)" }.sorted().joined(separator: ",")
			return "\(child.tag)(\(attrs))"
		}.joined(separator: "+")
		WhatsAppLog.logger.notice("call stanza from=\(node.attrs["from"] ?? "-", privacy: .public) participant=\(node.attrs["participant"] ?? "-", privacy: .public) \(actions, privacy: .public)")

		guard let chatID = node.attrs["from"], let infoChild = node.allChildren.first else {
			if let ack = StanzaAck.build(for: node) {
				try? await sendNode(ack)
			}

			return true
		}

		guard let callID = infoChild.attrs["call-id"],
			  let from = infoChild.attrs["from"] ?? infoChild.attrs["call-creator"] else {
			if let ack = StanzaAck.build(for: node) {
				try? await sendNode(ack)
			}

			return true
		}

		let status = IncomingCallStatusMapper.status(from: infoChild)
		let date = Date(timeIntervalSince1970: TimeInterval(node.attrs["t"].flatMap(Int64.init) ?? 0))

		// Acknowledged first: distributing a key can take a while, and the sender is waiting on this.
		if status == .groupUpdate || status == .groupEpoch {
			if let ack = StanzaAck.build(for: node) {
				try? await sendNode(ack)
			}
			if status == .groupUpdate {
				await handleGroupUpdateStanza(node, action: infoChild, chatID: chatID, date: date)
			} else {
				await handleGroupEpochStanza(node, action: infoChild, chatID: chatID, date: date)
			}

			return true
		}

		let cachedCall = callOfferCache[callID]
		// A key alone says nothing: only a roster makes this a group call.
		let isKnownGroup = cachedCall?.isGroup == true || groupCalls[callID]?.state.snapshot != nil
		let sender = node.attrs["participant"] ?? chatID
		let me = authenticationState?.credentials.me
		let isFromOwnAccount = me.map { CallJID.isSameUser(sender, $0.id) } == true
			|| me?.lid.map { CallJID.isSameUser(sender, $0) } == true

		// A hang-up in a group is one person leaving, which the roster says. Only the creator or the
		// service can end the call for everyone.
		if status == .terminate || status == .timeout, isKnownGroup,
		   !isAuthorizedGroupRosterWriter(sender, record: groupCalls[callID], creator: from, callID: callID) {
			WhatsAppLog.logger.notice("group call \(callID, privacy: .public): terminate from someone who cannot end it")
			if let ack = StanzaAck.build(for: node) {
				try? await sendNode(ack)
			}
			return true
		}

		let groupSnapshot = status == .offer ? admitGroupOffer(infoChild, callID: callID, creator: from) : nil
		if status == .offer || status == .preaccept || status == .accept {
			noteCallCapability(in: infoChild, sender: sender, callID: callID, creator: from)
		}
		let call = WhatsAppCallEvent(
			chatID: chatID,
			from: from,
			callerPN: infoChild.attrs["caller_pn"] ?? cachedCall?.callerPN,
			isGroup: status == .offer ? callIsGroup(infoChild) : cachedCall?.isGroup,
			groupJID: status == .offer ? (infoChild.attrs["group-jid"] ?? groupSnapshot?.groupJID) : cachedCall?.groupJID,
			id: callID,
			date: date,
			isVideo: status == .offer
				? (infoChild.firstChild(named: "video") != nil || infoChild.attrs["media"] == "video" || groupSnapshot?.isVideo == true)
				: cachedCall?.isVideo,
			status: status,
			offline: node.attrs["offline"] != nil,
			latencyMs: callLatency(from: infoChild, status: status),
			senderJID: node.attrs["participant"] ?? chatID,
			reason: infoChild.attrs["reason"],
			videoState: status == .video ? infoChild.attrs["state"].flatMap(Int.init) : nil,
			videoOrientation: callVideoOrientation(in: infoChild),
			groupUpdate: groupSnapshot,
			isMuted: status == .mute ? infoChild.attrs["mute-state"] == "1" : nil,
			isNotice: infoChild.tag == "offer_notice",
			isFromOwnAccount: isFromOwnAccount,
			isJoinable: status != .offer && infoChild.attrs["joinable"] == "1"
		)

		if status == .offer {
			callOfferCache[call.id] = call
			callOfferNodes[call.id] = node
		} else if callShouldClearOffer(status), !call.isDeviceOnlyReject,
				  // Someone else answering or turning down a group call leaves it ringing here.
				  !(isKnownGroup && !isFromOwnAccount && (status == .accept || status == .reject)) {
			callOfferCache.removeValue(forKey: call.id)
			callOfferNodes.removeValue(forKey: call.id)
			// Another device of this account answering says nothing about a call this one is in, and its
			// roster and keys go on being needed. Only the end of the call retires them.
			if isKnownGroup, status == .terminate || status == .timeout, !call.isJoinable {
				forgetGroupCall(id: call.id)
			}
		}

		if infoChild.tag == "offer", let stanzaID = node.attrs["id"], let creator = infoChild.attrs["call-creator"] {
			try? await sendNode(CallStanzaBuilder.offerReceipt(
				callID: callID,
				to: chatID,
				callCreator: creator,
				stanzaID: stanzaID,
				from: chatID.hasSuffix("@lid") ? me?.lid : me?.id
			))
		}

		eventContinuation.yield(.call([call]))
		// A mid-call `<video>` and some group controls are acknowledged by type: the sender's request times
		// out without it.
		if let ack = StanzaAck.build(for: node, type: callAckType(tag: infoChild.tag)) {
			try? await sendNode(ack)
		}

		return true
	}
}

extension WhatsAppClient {
	/// Commits the roster an offer carries, unless a newer one got here first, and returns what is current.
	private func admitGroupOffer(_ offer: BinaryNode, callID: String, creator: String) -> GroupCallUpdate? {
		let snapshot: GroupCallUpdate?
		do {
			snapshot = try GroupCallUpdate.parse(offer: offer)
		} catch {
			WhatsAppLog.logger.error("group call \(callID, privacy: .public): unreadable offer roster: \(String(describing: error), privacy: .public)")
			return nil
		}
		guard let snapshot else {
			return nil
		}

		var record = groupCalls[callID] ?? GroupCallRecord(state: GroupCallState(callID: callID, callCreator: creator))
		_ = record.state.apply(snapshot)
		storeGroupCallRecord(record, for: callID)
		return record.state.snapshot
	}
}

private func callAckType(tag: String) -> String? {
	switch tag {
	case "video", "waiting_room_update", "user_action", "screen_share":
		tag
	default:
		nil
	}
}

private extension BinaryNode {
	var allChildren: [BinaryNode] {
		guard case let .nodes(children) = content else {
			return []
		}

		return children
	}
}

/// The rotation a stanza announces, on the action itself or on its `<video>` child. Anything outside
/// the four quarter turns is not announced at all, since zero is a real rotation.
private func callVideoOrientation(in node: BinaryNode) -> Int? {
	let raw = node.tag == "video" ? node.attrs["device_orientation"]
		: node.firstChild(named: "video")?.attrs["device_orientation"]
	return raw.flatMap(Int.init).flatMap { (0...3).contains($0) ? $0 : nil }
}

private func callIsGroup(_ node: BinaryNode) -> Bool {
	node.attrs["type"] == "group" || node.attrs["group-jid"] != nil || node.firstChild(named: "group_info") != nil
}

private func callShouldClearOffer(_ status: WhatsAppCallUpdateType) -> Bool {
	status == .reject || status == .accept || status == .timeout || status == .terminate
}

private func callLatency(from node: BinaryNode, status: WhatsAppCallUpdateType) -> Int? {
	guard status == .relaylatency else {
		return nil
	}

	return node.attrs["latency"].flatMap(Int.init)
		?? node.attrs["latency_ms"].flatMap(Int.init)
		?? node.attrs["latency-ms"].flatMap(Int.init)
}
