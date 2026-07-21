import Foundation

public struct WhatsAppDevice: Equatable, Sendable {
	public let jid: String
	public let user: String
	public let server: String
	public let device: Int?

	public init(jid: String, user: String, server: String, device: Int?) {
		self.jid = jid
		self.user = user
		self.server = server
		self.device = device
	}
}

public enum DeviceListUpdateAction: String, Equatable, Sendable {
	case add
	case remove
	case update
}

public struct DeviceListUpdate: Equatable, Sendable {
	public let user: String
	public let action: DeviceListUpdateAction
	public let deviceHash: String?
	public let devices: [WhatsAppDevice]

	public init(user: String, action: DeviceListUpdateAction, deviceHash: String?, devices: [WhatsAppDevice]) {
		self.user = user
		self.action = action
		self.deviceHash = deviceHash
		self.devices = devices
	}
}
