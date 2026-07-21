public enum ReceivedLimitSharingTrigger: Equatable, Sendable {
	case unknown
	case chatSetting
	case bizSupportsFBHosting
	case unknownGroup
	case unrecognized(Int)
}

public struct ReceivedLimitSharingContent: Equatable, Sendable {
	public let sharingLimited: Bool?
	public let trigger: ReceivedLimitSharingTrigger?
	public let settingTimestampMilliseconds: Int64?
	public let initiatedByMe: Bool?

	public init(
		sharingLimited: Bool?,
		trigger: ReceivedLimitSharingTrigger?,
		settingTimestampMilliseconds: Int64?,
		initiatedByMe: Bool?
	) {
		self.sharingLimited = sharingLimited
		self.trigger = trigger
		self.settingTimestampMilliseconds = settingTimestampMilliseconds
		self.initiatedByMe = initiatedByMe
	}
}
