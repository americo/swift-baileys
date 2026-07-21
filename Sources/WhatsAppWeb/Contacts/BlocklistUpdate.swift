import Foundation

public enum BlocklistUpdateType: Equatable, Sendable {
	case add
	case remove
}

public struct BlocklistUpdate: Equatable, Sendable {
	public let jids: [String]
	public let type: BlocklistUpdateType

	public init(jids: [String], type: BlocklistUpdateType) {
		self.jids = jids
		self.type = type
	}
}
