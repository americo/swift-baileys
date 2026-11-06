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
	/// A mid-call change of the peer's video, carried by `videoState`.
	case video
	/// A committed group roster, carried by `groupUpdate`.
	case groupUpdate
	/// A new shared group media key, carried by `groupEpoch`.
	case groupEpoch
	/// A participant's microphone, carried by `isMuted`.
	case mute
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
	/// The raw `state` of a `.video` update (`CallVideoState`, when it is one this client knows).
	public let videoState: Int?
	/// Quarter turns the sender's camera is rotated by, on stanzas that announce it.
	public let videoOrientation: Int?
	/// The committed roster of a `.groupUpdate`, or of a group `.offer`.
	public let groupUpdate: GroupCallUpdate?
	public let groupEpoch: GroupCallEpoch?
	/// The state a `.mute` announces.
	public let isMuted: Bool?
	/// A group call's notice to its members, which cannot be answered. The call itself has an `<offer>`.
	public let isNotice: Bool
	/// Sent by another device of this account, which decides a ringing group call for this one too.
	public let isFromOwnAccount: Bool
	/// On a `.terminate`: it ends the call for this device only, and the call can be joined again.
	public let isJoinable: Bool

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
		reason: String? = nil,
		videoState: Int? = nil,
		videoOrientation: Int? = nil,
		groupUpdate: GroupCallUpdate? = nil,
		groupEpoch: GroupCallEpoch? = nil,
		isMuted: Bool? = nil,
		isNotice: Bool = false,
		isFromOwnAccount: Bool = false,
		isJoinable: Bool = false
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
		self.videoState = videoState
		self.videoOrientation = videoOrientation
		self.groupUpdate = groupUpdate
		self.groupEpoch = groupEpoch
		self.isMuted = isMuted
		self.isNotice = isNotice
		self.isFromOwnAccount = isFromOwnAccount
		self.isJoinable = isJoinable
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
