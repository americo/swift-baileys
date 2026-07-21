import Foundation

public struct ReceivedMessagePollUpdate: Equatable, Sendable {
	public let key: WhatsAppMessageKey
	public let pollUpdateMessageKey: WhatsAppMessageKey
	public let encryptedPayload: Data?
	public let encryptedIV: Data?
	public let senderTimestampMilliseconds: Int64?
	public let selectedOptionHashes: [Data]?

	public init(
		key: WhatsAppMessageKey,
		pollUpdateMessageKey: WhatsAppMessageKey,
		encryptedPayload: Data?,
		encryptedIV: Data?,
		senderTimestampMilliseconds: Int64?,
		selectedOptionHashes: [Data]? = nil
	) {
		self.key = key
		self.pollUpdateMessageKey = pollUpdateMessageKey
		self.encryptedPayload = encryptedPayload
		self.encryptedIV = encryptedIV
		self.senderTimestampMilliseconds = senderTimestampMilliseconds
		self.selectedOptionHashes = selectedOptionHashes
	}
}

public struct PollVoteDecryptionContext: Equatable, Sendable {
	public let pollMessageID: String
	public let pollCreatorJID: String
	public let voterJID: String
	public let pollEncKey: Data

	public init(pollMessageID: String, pollCreatorJID: String, voterJID: String, pollEncKey: Data) {
		self.pollMessageID = pollMessageID
		self.pollCreatorJID = pollCreatorJID
		self.voterJID = voterJID
		self.pollEncKey = pollEncKey
	}
}

public protocol PollVoteContextResolving: Sendable {
	func context(
		for key: WhatsAppMessageKey,
		pollUpdateMessageKey: WhatsAppMessageKey
	) async throws -> PollVoteDecryptionContext?
}
