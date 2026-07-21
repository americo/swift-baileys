import Foundation

public enum ReceivedPollContentType: Equatable, Sendable {
	case unknown
	case text
	case image
	case unrecognized(Int)
}

public enum ReceivedPollType: Equatable, Sendable {
	case poll
	case quiz
	case unrecognized(Int)
}

public struct ReceivedPollOption: Equatable, Sendable {
	public let name: String?
	public let hash: String?

	public init(name: String?, hash: String?) {
		self.name = name
		self.hash = hash
	}
}

public struct ReceivedPollCreationContent: Equatable, Sendable {
	public let name: String?
	public let options: [ReceivedPollOption]
	public let selectableOptionsCount: UInt32?
	public let encryptedKey: Data?
	public let contentType: ReceivedPollContentType
	public let pollType: ReceivedPollType
	public let correctAnswer: ReceivedPollOption?

	public init(
		name: String?,
		options: [ReceivedPollOption],
		selectableOptionsCount: UInt32?,
		encryptedKey: Data?,
		contentType: ReceivedPollContentType,
		pollType: ReceivedPollType,
		correctAnswer: ReceivedPollOption?
	) {
		self.name = name
		self.options = options
		self.selectableOptionsCount = selectableOptionsCount
		self.encryptedKey = encryptedKey
		self.contentType = contentType
		self.pollType = pollType
		self.correctAnswer = correctAnswer
	}
}

public struct ReceivedPollUpdateContent: Equatable, Sendable {
	public let pollCreationMessageKey: ReceivedMessageKey?
	public let encryptedPayload: Data?
	public let encryptedIV: Data?
	public let senderTimestampMilliseconds: Int64?

	public init(
		pollCreationMessageKey: ReceivedMessageKey?,
		encryptedPayload: Data?,
		encryptedIV: Data?,
		senderTimestampMilliseconds: Int64?
	) {
		self.pollCreationMessageKey = pollCreationMessageKey
		self.encryptedPayload = encryptedPayload
		self.encryptedIV = encryptedIV
		self.senderTimestampMilliseconds = senderTimestampMilliseconds
	}
}

public struct ReceivedPollResultVote: Equatable, Sendable {
	public let optionName: String?
	public let voteCount: Int64?

	public init(optionName: String?, voteCount: Int64?) {
		self.optionName = optionName
		self.voteCount = voteCount
	}
}

public struct ReceivedPollResultSnapshotContent: Equatable, Sendable {
	public let name: String?
	public let votes: [ReceivedPollResultVote]
	public let pollType: ReceivedPollType

	public init(name: String?, votes: [ReceivedPollResultVote], pollType: ReceivedPollType) {
		self.name = name
		self.votes = votes
		self.pollType = pollType
	}
}
