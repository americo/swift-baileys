import Foundation

public enum AppStateCollectionName: String, CaseIterable, Sendable {
	case criticalBlock = "critical_block"
	case criticalUnblockLow = "critical_unblock_low"
	case regular
	case regularHigh = "regular_high"
	case regularLow = "regular_low"

	var patchType: ChatModificationPatchType {
		switch self {
		case .criticalBlock:
			.criticalBlock
		case .criticalUnblockLow:
			.criticalUnblockLow
		case .regular:
			.regular
		case .regularHigh:
			.regularHigh
		case .regularLow:
			.regularLow
		}
	}
}

public struct AppStateSyncRequest: Equatable, Sendable {
	public let collections: [String]

	public init(collections: [String]) {
		self.collections = collections
	}
}
