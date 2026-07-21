public enum ReceivedScheduledCallType: Equatable, Sendable {
	case unknown
	case voice
	case video
	case unrecognized(Int)
}

public struct ReceivedScheduledCallCreationContent: Equatable, Sendable {
	public let scheduledTimestampMilliseconds: Int64?
	public let callType: ReceivedScheduledCallType
	public let title: String?

	public init(
		scheduledTimestampMilliseconds: Int64?,
		callType: ReceivedScheduledCallType,
		title: String?
	) {
		self.scheduledTimestampMilliseconds = scheduledTimestampMilliseconds
		self.callType = callType
		self.title = title
	}
}
