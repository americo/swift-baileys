import Foundation

public enum WhatsAppCallUpdateType: String, Sendable {
	case offer
	case ringing
	case preaccept
	case transport
	case relaylatency
	case timeout
	case reject
	case accept
	case terminate
}

public struct WhatsAppCallEvent: Equatable, Sendable {
	public let chatID: String
	public let from: String
	public let callerPN: String?
	public let isGroup: Bool?
	public let groupJID: String?
	public let id: String
	public let date: Date
	public let isVideo: Bool?
	public let status: WhatsAppCallUpdateType
	public let offline: Bool
	public let latencyMs: Int?

	public init(
		chatID: String,
		from: String,
		callerPN: String? = nil,
		isGroup: Bool? = nil,
		groupJID: String? = nil,
		id: String,
		date: Date,
		isVideo: Bool? = nil,
		status: WhatsAppCallUpdateType,
		offline: Bool,
		latencyMs: Int? = nil
	) {
		self.chatID = chatID
		self.from = from
		self.callerPN = callerPN
		self.isGroup = isGroup
		self.groupJID = groupJID
		self.id = id
		self.date = date
		self.isVideo = isVideo
		self.status = status
		self.offline = offline
		self.latencyMs = latencyMs
	}
}
