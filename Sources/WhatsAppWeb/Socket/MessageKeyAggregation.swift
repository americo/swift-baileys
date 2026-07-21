import Foundation

public struct MessageKeyAggregation: Equatable, Sendable {
	public let jid: String
	public let participant: String?
	public let messageIDs: [String]

	public init(jid: String, participant: String?, messageIDs: [String]) {
		self.jid = jid
		self.participant = participant
		self.messageIDs = messageIDs
	}
}

public enum MessageKeyAggregator {
	public static func aggregateMessageKeysNotFromMe(_ keys: [WhatsAppMessageKey]) -> [MessageKeyAggregation] {
		var groups: [MessageKeyAggregation] = []

		for key in keys where !key.fromMe {
			guard let jid = key.remoteJID, let id = key.id else {
				continue
			}

			if let index = groups.firstIndex(where: { $0.jid == jid && $0.participant == key.participant }) {
				let group = groups[index]
				groups[index] = MessageKeyAggregation(
					jid: group.jid,
					participant: group.participant,
					messageIDs: group.messageIDs + [id]
				)
			} else {
				groups.append(MessageKeyAggregation(jid: jid, participant: key.participant, messageIDs: [id]))
			}
		}

		return groups
	}
}
