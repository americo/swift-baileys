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
	/// The device that sent this stanza. An `accept` names the device that answered the call.
	public let senderJID: String?
	/// The stanza's `reason`, such as `busy` on a `reject`.
	public let reason: String?

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
		latencyMs: Int? = nil,
		senderJID: String? = nil,
		reason: String? = nil
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
		self.senderJID = senderJID
		self.reason = reason
	}

	/// A `reject` that speaks only for the device that sent it, so the call stays alive.
	///
	/// `busy`, `enc` and `uncallable` say that one device cannot take the call, and the others go on
	/// ringing. Hosted devices of an account cannot take a voice call at all and turn down every offer
	/// as soon as it arrives, so whatever they send decides nothing either.
	public var isDeviceOnlyReject: Bool {
		guard status == .reject else {
			return false
		}

		return reason.map(Self.deviceOnlyRejectReasons.contains) == true
			|| senderJID?.contains("@hosted") == true
	}

	private static let deviceOnlyRejectReasons: Set<String> = ["busy", "enc", "uncallable"]
}
