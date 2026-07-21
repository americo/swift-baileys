public enum SettingsUpdateValue: Equatable, Sendable {
	case string(String)
	case bool(Bool)
	case int(Int)
	case statusPrivacy(StatusPrivacyUpdate)
}

public struct StatusPrivacyUpdate: Equatable, Sendable {
	public let mode: Int
	public let userJIDs: [String]

	public init(mode: Int, userJIDs: [String]) {
		self.mode = mode
		self.userJIDs = userJIDs
	}
}

public struct SettingsUpdate: Equatable, Sendable {
	public let setting: String
	public let value: SettingsUpdateValue

	public init(setting: String, value: SettingsUpdateValue) {
		self.setting = setting
		self.value = value
	}
}
