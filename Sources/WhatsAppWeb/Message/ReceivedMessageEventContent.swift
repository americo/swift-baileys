import Foundation

public struct ReceivedMessageKey: Equatable, Sendable {
	public let remoteJID: String?
	public let fromMe: Bool
	public let id: String?
	public let participant: String?

	public init(remoteJID: String?, fromMe: Bool, id: String?, participant: String?) {
		self.remoteJID = remoteJID
		self.fromMe = fromMe
		self.id = id
		self.participant = participant
	}
}

public struct ReceivedReactionContent: Equatable, Sendable {
	public let key: ReceivedMessageKey?
	public let text: String?
	public let groupingKey: String?
	public let senderTimestampMilliseconds: Int64?

	public init(
		key: ReceivedMessageKey?,
		text: String?,
		groupingKey: String?,
		senderTimestampMilliseconds: Int64?
	) {
		self.key = key
		self.text = text
		self.groupingKey = groupingKey
		self.senderTimestampMilliseconds = senderTimestampMilliseconds
	}
}

public struct ReceivedMessageRevokedContent: Equatable, Sendable {
	public let key: ReceivedMessageKey?
	public let timestampMilliseconds: Int64?

	public init(key: ReceivedMessageKey?, timestampMilliseconds: Int64?) {
		self.key = key
		self.timestampMilliseconds = timestampMilliseconds
	}
}

public struct ReceivedMessageEditedContent: Equatable, Sendable {
	public let key: ReceivedMessageKey?
	public let content: ReceivedMessageContent?
	public let timestampMilliseconds: Int64?

	public init(
		key: ReceivedMessageKey?,
		content: ReceivedMessageContent?,
		timestampMilliseconds: Int64?
	) {
		self.key = key
		self.content = content
		self.timestampMilliseconds = timestampMilliseconds
	}
}

public enum ReceivedMessagePinAction: Equatable, Sendable {
	case unknown
	case pinForAll
	case unpinForAll
	case unrecognized(Int)
}

public struct ReceivedMessagePinContent: Equatable, Sendable {
	public let key: ReceivedMessageKey?
	public let action: ReceivedMessagePinAction
	public let senderTimestampMilliseconds: Int64?

	public init(
		key: ReceivedMessageKey?,
		action: ReceivedMessagePinAction,
		senderTimestampMilliseconds: Int64?
	) {
		self.key = key
		self.action = action
		self.senderTimestampMilliseconds = senderTimestampMilliseconds
	}
}

public enum ReceivedMessageKeepAction: Equatable, Sendable {
	case unknown
	case keepForAll
	case undoKeepForAll
	case unrecognized(Int)
}

public struct ReceivedMessageKeepContent: Equatable, Sendable {
	public let key: ReceivedMessageKey?
	public let action: ReceivedMessageKeepAction
	public let timestampMilliseconds: Int64?

	public init(
		key: ReceivedMessageKey?,
		action: ReceivedMessageKeepAction,
		timestampMilliseconds: Int64?
	) {
		self.key = key
		self.action = action
		self.timestampMilliseconds = timestampMilliseconds
	}
}

public struct ReceivedNewsletterAdminInviteContent: Equatable, Sendable {
	public let newsletterJID: String?
	public let newsletterName: String?
	public let caption: String?
	public let inviteExpiration: Int64?
	public let jpegThumbnail: Data?

	public init(
		newsletterJID: String?,
		newsletterName: String?,
		caption: String?,
		inviteExpiration: Int64?,
		jpegThumbnail: Data?
	) {
		self.newsletterJID = newsletterJID
		self.newsletterName = newsletterName
		self.caption = caption
		self.inviteExpiration = inviteExpiration
		self.jpegThumbnail = jpegThumbnail
	}
}

public struct ReceivedNewsletterFollowerInviteContent: Equatable, Sendable {
	public let newsletterJID: String?
	public let newsletterName: String?
	public let caption: String?
	public let jpegThumbnail: Data?

	public init(
		newsletterJID: String?,
		newsletterName: String?,
		caption: String?,
		jpegThumbnail: Data?
	) {
		self.newsletterJID = newsletterJID
		self.newsletterName = newsletterName
		self.caption = caption
		self.jpegThumbnail = jpegThumbnail
	}
}

public enum ReceivedCallLogOutcome: Equatable, Sendable {
	case connected
	case missed
	case failed
	case rejected
	case acceptedElsewhere
	case ongoing
	case silencedByDnd
	case silencedUnknownCaller
	case unrecognized(Int)
}

public enum ReceivedCallLogType: Equatable, Sendable {
	case regular
	case scheduledCall
	case voiceChat
	case unrecognized(Int)
}

public struct ReceivedCallLogParticipant: Equatable, Sendable {
	public let jid: String?
	public let outcome: ReceivedCallLogOutcome?

	public init(jid: String?, outcome: ReceivedCallLogOutcome?) {
		self.jid = jid
		self.outcome = outcome
	}
}

public struct ReceivedCallLogContent: Equatable, Sendable {
	public let isVideo: Bool?
	public let outcome: ReceivedCallLogOutcome?
	public let durationSeconds: Int64?
	public let callType: ReceivedCallLogType?
	public let participants: [ReceivedCallLogParticipant]

	public init(
		isVideo: Bool?,
		outcome: ReceivedCallLogOutcome?,
		durationSeconds: Int64?,
		callType: ReceivedCallLogType?,
		participants: [ReceivedCallLogParticipant]
	) {
		self.isVideo = isVideo
		self.outcome = outcome
		self.durationSeconds = durationSeconds
		self.callType = callType
		self.participants = participants
	}
}
