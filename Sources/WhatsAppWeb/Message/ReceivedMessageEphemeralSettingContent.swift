public enum ReceivedDisappearingModeInitiator: Equatable, Sendable {
	case changedInChat
	case initiatedByMe
	case initiatedByOther
	case businessUpgradeFBHosting
	case unrecognized(Int)
}

public enum ReceivedDisappearingModeTrigger: Equatable, Sendable {
	case unknown
	case chatSetting
	case accountSetting
	case bulkChange
	case bizSupportsFBHosting
	case unknownGroups
	case unrecognized(Int)
}

public struct ReceivedDisappearingModeContent: Equatable, Sendable {
	public let initiator: ReceivedDisappearingModeInitiator?
	public let trigger: ReceivedDisappearingModeTrigger?
	public let initiatorDeviceJID: String?
	public let initiatedByMe: Bool?

	public init(
		initiator: ReceivedDisappearingModeInitiator?,
		trigger: ReceivedDisappearingModeTrigger?,
		initiatorDeviceJID: String?,
		initiatedByMe: Bool?
	) {
		self.initiator = initiator
		self.trigger = trigger
		self.initiatorDeviceJID = initiatorDeviceJID
		self.initiatedByMe = initiatedByMe
	}
}

public struct ReceivedEphemeralSettingContent: Equatable, Sendable {
	public let expirationSeconds: UInt32?
	public let settingTimestampSeconds: Int64?
	public let disappearingMode: ReceivedDisappearingModeContent?

	public init(
		expirationSeconds: UInt32?,
		settingTimestampSeconds: Int64?,
		disappearingMode: ReceivedDisappearingModeContent?
	) {
		self.expirationSeconds = expirationSeconds
		self.settingTimestampSeconds = settingTimestampSeconds
		self.disappearingMode = disappearingMode
	}
}
