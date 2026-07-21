import Foundation

public enum ReceivedStatusNotificationType: Equatable, Sendable {
	case unknown
	case statusAddYours
	case statusReshare
	case statusQuestionAnswerReshare
	case unrecognized(Int)
}

public struct ReceivedStatusNotificationContent: Equatable, Sendable {
	public let responseMessageKey: ReceivedMessageKey?
	public let originalMessageKey: ReceivedMessageKey?
	public let type: ReceivedStatusNotificationType?

	public init(
		responseMessageKey: ReceivedMessageKey?,
		originalMessageKey: ReceivedMessageKey?,
		type: ReceivedStatusNotificationType?
	) {
		self.responseMessageKey = responseMessageKey
		self.originalMessageKey = originalMessageKey
		self.type = type
	}
}

public struct ReceivedStatusQuestionAnswerContent: Equatable, Sendable {
	public let key: ReceivedMessageKey?
	public let text: String?

	public init(key: ReceivedMessageKey?, text: String?) {
		self.key = key
		self.text = text
	}
}

public enum ReceivedStatusQuotedType: Equatable, Sendable {
	case unknown
	case questionAnswer
	case unrecognized(Int)
}

public struct ReceivedStatusQuotedContent: Equatable, Sendable {
	public let type: ReceivedStatusQuotedType?
	public let text: String?
	public let thumbnail: Data?
	public let originalStatusID: ReceivedMessageKey?

	public init(
		type: ReceivedStatusQuotedType?,
		text: String?,
		thumbnail: Data?,
		originalStatusID: ReceivedMessageKey?
	) {
		self.type = type
		self.text = text
		self.thumbnail = thumbnail
		self.originalStatusID = originalStatusID
	}
}

public enum ReceivedStatusStickerInteractionType: Equatable, Sendable {
	case unknown
	case reaction
	case unrecognized(Int)
}

public struct ReceivedStatusStickerInteractionContent: Equatable, Sendable {
	public let key: ReceivedMessageKey?
	public let stickerKey: String?
	public let type: ReceivedStatusStickerInteractionType?

	public init(
		key: ReceivedMessageKey?,
		stickerKey: String?,
		type: ReceivedStatusStickerInteractionType?
	) {
		self.key = key
		self.stickerKey = stickerKey
		self.type = type
	}
}
