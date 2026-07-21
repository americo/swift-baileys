import Foundation

public struct ReachoutTimelockUpdate: Equatable, Sendable {
	public let isActive: Bool
	public let timeEnforcementEnds: Date?
	public let enforcementType: String

	public init(isActive: Bool, timeEnforcementEnds: Date? = nil, enforcementType: String) {
		self.isActive = isActive
		self.timeEnforcementEnds = timeEnforcementEnds
		self.enforcementType = enforcementType
	}
}

public struct MessageCappingUpdate: Equatable, Sendable {
	public let totalQuota: Int?
	public let usedQuota: Int?
	public let cycleStartTimestamp: String?
	public let cycleEndTimestamp: String?
	public let serverSentTimestamp: String?
	public let oteStatus: String?
	public let mvStatus: String?
	public let cappingStatus: String?

	public init(
		totalQuota: Int? = nil,
		usedQuota: Int? = nil,
		cycleStartTimestamp: String? = nil,
		cycleEndTimestamp: String? = nil,
		serverSentTimestamp: String? = nil,
		oteStatus: String? = nil,
		mvStatus: String? = nil,
		cappingStatus: String? = nil
	) {
		self.totalQuota = totalQuota
		self.usedQuota = usedQuota
		self.cycleStartTimestamp = cycleStartTimestamp
		self.cycleEndTimestamp = cycleEndTimestamp
		self.serverSentTimestamp = serverSentTimestamp
		self.oteStatus = oteStatus
		self.mvStatus = mvStatus
		self.cappingStatus = cappingStatus
	}
}
