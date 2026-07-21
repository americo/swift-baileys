import Foundation

public enum ReceivedAIRichResponseMessageType: Equatable, Sendable {
	case unknown
	case standard
	case unrecognized(Int)
}

public enum ReceivedAIRichResponseSubMessageType: Equatable, Sendable {
	case unknown
	case gridImage
	case text
	case inlineImage
	case table
	case code
	case dynamic
	case map
	case latex
	case contentItems
	case unrecognized(Int)
}

public struct ReceivedAIRichResponseSubMessageContent: Equatable, Sendable {
	public let type: ReceivedAIRichResponseSubMessageType?
	public let text: String?

	public init(type: ReceivedAIRichResponseSubMessageType?, text: String?) {
		self.type = type
		self.text = text
	}
}

public struct ReceivedAIRichResponseContent: Equatable, Sendable {
	public let messageType: ReceivedAIRichResponseMessageType?
	public let submessages: [ReceivedAIRichResponseSubMessageContent]
	public let unifiedResponseData: Data?
	public let serializedBytes: Data?

	public init(
		messageType: ReceivedAIRichResponseMessageType?,
		submessages: [ReceivedAIRichResponseSubMessageContent],
		unifiedResponseData: Data?,
		serializedBytes: Data? = nil
	) {
		self.messageType = messageType
		self.submessages = submessages
		self.unifiedResponseData = unifiedResponseData
		self.serializedBytes = serializedBytes
	}
}
