import Foundation

public enum ReceivedGroupInviteType: Equatable, Sendable {
	case `default`
	case parent
	case unrecognized(Int)
}

public struct ReceivedGroupInviteContent: Equatable, Sendable {
	public let groupJID: String?
	public let inviteCode: String?
	public let inviteExpiration: Int64?
	public let groupName: String?
	public let caption: String?
	public let groupType: ReceivedGroupInviteType
	public let jpegThumbnail: Data?

	public init(
		groupJID: String?,
		inviteCode: String?,
		inviteExpiration: Int64?,
		groupName: String?,
		caption: String?,
		groupType: ReceivedGroupInviteType,
		jpegThumbnail: Data?
	) {
		self.groupJID = groupJID
		self.inviteCode = inviteCode
		self.inviteExpiration = inviteExpiration
		self.groupName = groupName
		self.caption = caption
		self.groupType = groupType
		self.jpegThumbnail = jpegThumbnail
	}
}
