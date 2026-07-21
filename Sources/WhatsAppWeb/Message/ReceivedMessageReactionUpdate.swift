import Foundation

public struct ReceivedMessageReactionUpdate: Equatable, Sendable {
	public let key: WhatsAppMessageKey
	public let reactionMessageKey: WhatsAppMessageKey
	public let text: String?
	public let groupingKey: String?
	public let senderTimestampMilliseconds: Int64?

	public init(
		key: WhatsAppMessageKey,
		reactionMessageKey: WhatsAppMessageKey,
		text: String?,
		groupingKey: String?,
		senderTimestampMilliseconds: Int64?
	) {
		self.key = key
		self.reactionMessageKey = reactionMessageKey
		self.text = text
		self.groupingKey = groupingKey
		self.senderTimestampMilliseconds = senderTimestampMilliseconds
	}
}
