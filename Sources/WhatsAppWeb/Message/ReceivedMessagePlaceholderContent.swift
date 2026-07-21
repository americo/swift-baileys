public enum ReceivedPlaceholderType: Equatable, Sendable {
	case maskLinkedDevices
	case unrecognized(Int)
}

public struct ReceivedPlaceholderContent: Equatable, Sendable {
	public let type: ReceivedPlaceholderType?

	public init(type: ReceivedPlaceholderType?) {
		self.type = type
	}
}
