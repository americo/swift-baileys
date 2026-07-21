public struct ReceivedMessageStubContent: Equatable, Sendable {
	public let type: ReceivedMessageStubType
	public let parameters: [String]

	public init(type: ReceivedMessageStubType, parameters: [String]) {
		self.type = type
		self.parameters = parameters
	}
}

public struct ReceivedMessageStubType: RawRepresentable, Equatable, Sendable {
	public let rawValue: Int

	public init(rawValue: Int) {
		self.rawValue = rawValue
	}

	public static let unknown = Self(rawValue: 0)
	public static let revoke = Self(rawValue: 1)
	public static let ciphertext = Self(rawValue: 2)
	public static let futureproof = Self(rawValue: 3)
	public static let groupCreate = Self(rawValue: 20)
	public static let groupChangeSubject = Self(rawValue: 21)
	public static let groupChangeIcon = Self(rawValue: 22)
	public static let groupChangeInviteLink = Self(rawValue: 23)
	public static let groupChangeDescription = Self(rawValue: 24)
	public static let groupChangeRestrict = Self(rawValue: 25)
	public static let groupChangeAnnounce = Self(rawValue: 26)
	public static let groupParticipantAdd = Self(rawValue: 27)
	public static let groupParticipantRemove = Self(rawValue: 28)
	public static let groupParticipantPromote = Self(rawValue: 29)
	public static let groupParticipantDemote = Self(rawValue: 30)
	public static let groupParticipantInvite = Self(rawValue: 31)
	public static let groupParticipantLeave = Self(rawValue: 32)
	public static let groupParticipantChangeNumber = Self(rawValue: 33)
	public static let callMissedVoice = Self(rawValue: 40)
	public static let callMissedVideo = Self(rawValue: 41)
	public static let callMissedGroupVoice = Self(rawValue: 45)
	public static let callMissedGroupVideo = Self(rawValue: 46)
	public static let groupParticipantAddRequestJoin = Self(rawValue: 71)
	public static let groupMembershipJoinApprovalMode = Self(rawValue: 145)
	public static let groupMemberAddMode = Self(rawValue: 171)
	public static let groupMembershipJoinApprovalRequestNonAdminAdd = Self(rawValue: 172)
}
