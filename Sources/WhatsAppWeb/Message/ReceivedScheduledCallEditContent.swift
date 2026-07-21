public enum ReceivedScheduledCallEditType: Equatable, Sendable {
	case unknown
	case cancel
	case unrecognized(Int)
}

public struct ReceivedScheduledCallEditContent: Equatable, Sendable {
	public let key: ReceivedMessageKey?
	public let editType: ReceivedScheduledCallEditType

	public init(key: ReceivedMessageKey?, editType: ReceivedScheduledCallEditType) {
		self.key = key
		self.editType = editType
	}
}
