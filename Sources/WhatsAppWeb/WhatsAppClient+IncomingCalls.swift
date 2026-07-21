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
		let cachedCall = callOfferCache[callID]
		let call = WhatsAppCallEvent(
			chatID: chatID,
			from: from,
			callerPN: infoChild.attrs["caller_pn"] ?? cachedCall?.callerPN,
			isGroup: status == .offer ? callIsGroup(infoChild) : cachedCall?.isGroup,
			groupJID: status == .offer ? infoChild.attrs["group-jid"] : cachedCall?.groupJID,
			id: callID,
			date: Date(timeIntervalSince1970: TimeInterval(node.attrs["t"].flatMap(Int64.init) ?? 0)),
			isVideo: status == .offer ? (infoChild.firstChild(named: "video") != nil) : cachedCall?.isVideo,
			status: status,
			offline: node.attrs["offline"] != nil,
			latencyMs: callLatency(from: infoChild, status: status)
		)

		if status == .offer {
			callOfferCache[call.id] = call
		} else if callShouldClearOffer(status) {
			callOfferCache.removeValue(forKey: call.id)
		}

		eventContinuation.yield(.call([call]))
		if let ack = StanzaAck.build(for: node) {
			try? await sendNode(ack)
		}

		return true
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

private func callIsGroup(_ node: BinaryNode) -> Bool {
	node.attrs["type"] == "group" || node.attrs["group-jid"] != nil
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
