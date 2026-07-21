import Foundation

extension WhatsAppClient {
	func handlePresenceNode(_ node: BinaryNode) async -> Bool {
		guard node.tag == "presence" || node.tag == "chatstate", let jid = node.attrs["from"] else {
			return false
		}
		if jid != "@s.whatsapp.net", configuration.shouldIgnoreJID(jid) == true {
			return false
		}

		let participant = node.attrs["participant"] ?? jid
		let presence: WhatsAppPresenceData?

		if node.tag == "presence" {
			presence = WhatsAppPresenceData(
				lastKnownPresence: node.attrs["type"] == "unavailable" ? .unavailable : .available,
				lastSeen: node.attrs["last"].flatMap(UInt64.init),
				groupOnlineCount: node.attrs["count"].flatMap(Int.init)
			)
		} else if case let .nodes(children) = node.content, let firstChild = children.first {
			let lastKnownPresence: WhatsAppPresence
			if firstChild.attrs["media"] == "audio" {
				lastKnownPresence = .recording
			} else if firstChild.tag == "paused" {
				lastKnownPresence = .available
			} else {
				lastKnownPresence = WhatsAppPresence(rawValue: firstChild.tag) ?? .available
			}

			presence = WhatsAppPresenceData(lastKnownPresence: lastKnownPresence)
		} else {
			presence = nil
		}

		guard let presence else {
			return false
		}

		eventContinuation.yield(.presenceUpdated(WhatsAppPresenceUpdate(
			id: jid,
			presences: [participant: presence]
		)))
		return true
	}
}
