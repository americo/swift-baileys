import Foundation

public enum GroupAddressingMode: String, Sendable {
	case pn
	case lid
}

public enum GroupParticipantAdmin: String, Sendable {
	case admin
	case superadmin
}

public enum GroupParticipantAction: String, Sendable {
	case add
	case remove
	case promote
	case demote
	case modify
}

public enum GroupMembershipApprovalAction: String, Sendable {
	case approve
	case reject
}

public enum GroupSetting: String, Sendable {
	case announcement
	case notAnnouncement = "not_announcement"
	case locked
	case unlocked
}

public enum GroupMemberAddMode: String, Sendable {
	case adminAdd = "admin_add"
	case allMemberAdd = "all_member_add"
}

public enum GroupJoinApprovalMode: String, Sendable {
	case on
	case off
}

public struct GroupParticipantUpdateResult: Equatable, Sendable {
	public let jid: String
	public let status: String
	public let content: BinaryNode?

	public init(jid: String, status: String, content: BinaryNode? = nil) {
		self.jid = jid
		self.status = status
		self.content = content
	}
}

public struct GroupMembershipApprovalRequest: Equatable, Sendable {
	public let jid: String
	public let requestMethod: String?
	public let requestedAt: Int64?

	public init(jid: String, requestMethod: String? = nil, requestedAt: Int64? = nil) {
		self.jid = jid
		self.requestMethod = requestMethod
		self.requestedAt = requestedAt
	}
}

public struct CommunityLinkedGroup: Equatable, Sendable {
	public let id: String?
	public let subject: String
	public let creation: Int64?
	public let owner: String?
	public let size: Int?

	public init(id: String?, subject: String, creation: Int64? = nil, owner: String? = nil, size: Int? = nil) {
		self.id = id
		self.subject = subject
		self.creation = creation
		self.owner = owner
		self.size = size
	}
}

public struct CommunityLinkedGroups: Equatable, Sendable {
	public let communityJID: String
	public let isCommunity: Bool
	public let linkedGroups: [CommunityLinkedGroup]

	public init(communityJID: String, isCommunity: Bool, linkedGroups: [CommunityLinkedGroup]) {
		self.communityJID = communityJID
		self.isCommunity = isCommunity
		self.linkedGroups = linkedGroups
	}
}

public struct GroupParticipant: Equatable, Sendable {
	public let id: String
	public let phoneNumber: String?
	public let lid: String?
	public let username: String?
	public let admin: GroupParticipantAdmin?

	public init(
		id: String,
		phoneNumber: String? = nil,
		lid: String? = nil,
		username: String? = nil,
		admin: GroupParticipantAdmin? = nil
	) {
		self.id = id
		self.phoneNumber = phoneNumber
		self.lid = lid
		self.username = username
		self.admin = admin
	}
}

public struct GroupMetadata: Equatable, Sendable {
	public let id: String
	public let notify: String?
	public let addressingMode: GroupAddressingMode
	public let owner: String?
	public let ownerPn: String?
	public let ownerUsername: String?
	public let ownerCountryCode: String?
	public let subject: String
	public let subjectOwner: String?
	public let subjectOwnerPn: String?
	public let subjectOwnerUsername: String?
	public let subjectTime: Int64?
	public let creation: Int64?
	public let desc: String?
	public let descOwner: String?
	public let descOwnerPn: String?
	public let descOwnerUsername: String?
	public let descId: String?
	public let descTime: Int64?
	public let linkedParent: String?
	public let restrict: Bool
	public let announce: Bool
	public let memberAddMode: Bool
	public let joinApprovalMode: Bool
	public let isCommunity: Bool
	public let isCommunityAnnounce: Bool
	public let size: Int
	public let participants: [GroupParticipant]
	public let ephemeralDuration: Int64?

	public init(
		id: String,
		notify: String? = nil,
		addressingMode: GroupAddressingMode = .pn,
		owner: String? = nil,
		ownerPn: String? = nil,
		ownerUsername: String? = nil,
		ownerCountryCode: String? = nil,
		subject: String,
		subjectOwner: String? = nil,
		subjectOwnerPn: String? = nil,
		subjectOwnerUsername: String? = nil,
		subjectTime: Int64? = nil,
		creation: Int64? = nil,
		desc: String? = nil,
		descOwner: String? = nil,
		descOwnerPn: String? = nil,
		descOwnerUsername: String? = nil,
		descId: String? = nil,
		descTime: Int64? = nil,
		linkedParent: String? = nil,
		restrict: Bool = false,
		announce: Bool = false,
		memberAddMode: Bool = false,
		joinApprovalMode: Bool = false,
		isCommunity: Bool = false,
		isCommunityAnnounce: Bool = false,
		size: Int,
		participants: [GroupParticipant],
		ephemeralDuration: Int64? = nil
	) {
		self.id = id
		self.notify = notify
		self.addressingMode = addressingMode
		self.owner = owner
		self.ownerPn = ownerPn
		self.ownerUsername = ownerUsername
		self.ownerCountryCode = ownerCountryCode
		self.subject = subject
		self.subjectOwner = subjectOwner
		self.subjectOwnerPn = subjectOwnerPn
		self.subjectOwnerUsername = subjectOwnerUsername
		self.subjectTime = subjectTime
		self.creation = creation
		self.desc = desc
		self.descOwner = descOwner
		self.descOwnerPn = descOwnerPn
		self.descOwnerUsername = descOwnerUsername
		self.descId = descId
		self.descTime = descTime
		self.linkedParent = linkedParent
		self.restrict = restrict
		self.announce = announce
		self.memberAddMode = memberAddMode
		self.joinApprovalMode = joinApprovalMode
		self.isCommunity = isCommunity
		self.isCommunityAnnounce = isCommunityAnnounce
		self.size = size
		self.participants = participants
		self.ephemeralDuration = ephemeralDuration
	}
}

public enum GroupMetadataParserError: Error, Equatable, Sendable {
	case missingGroupNode
	case missingGroupID
	case serverError(code: Int, text: String)
}

public enum GroupMetadataParser {
	public static func parse(_ result: BinaryNode) throws -> GroupMetadata {
		try parse(result, nodeName: "group", defaultSubGroupTag: "default_sub_group")
	}

	public static func parseCommunity(_ result: BinaryNode) throws -> GroupMetadata {
		try parse(result, nodeName: "community", defaultSubGroupTag: "default_sub_community")
	}

	private static func parse(
		_ result: BinaryNode,
		nodeName: String,
		defaultSubGroupTag: String
	) throws -> GroupMetadata {
		guard let group = result.firstChild(named: nodeName) else {
			if let error = result.firstChild(named: "error") {
				throw GroupMetadataParserError.serverError(
					code: Int(error.attrs["code"] ?? "") ?? 500,
					text: error.attrs["text"] ?? "group metadata query failed"
				)
			}

			throw GroupMetadataParserError.missingGroupNode
		}

		guard let rawID = group.attrs["id"] else {
			throw GroupMetadataParserError.missingGroupID
		}

		let descNode = group.firstChild(named: "description")
		let participants = group.children(named: "participant").map { participant in
			let id = participant.attrs["jid"] ?? ""
			return GroupParticipant(
				id: id,
				phoneNumber: id.isLIDUserJID && (participant.attrs["phone_number"]?.isWhatsAppUserJID ?? false)
					? participant.attrs["phone_number"]
					: nil,
				lid: id.isWhatsAppUserJID && (participant.attrs["lid"]?.isLIDUserJID ?? false)
					? participant.attrs["lid"]
					: nil,
				username: participant.attrs["participant_username"] ?? participant.attrs["username"],
				admin: participant.attrs["type"].flatMap(GroupParticipantAdmin.init(rawValue:))
			)
		}

		return GroupMetadata(
			id: rawID.contains("@") ? rawID : JID.encode(user: rawID, server: JIDServer.group.rawValue),
			notify: group.attrs["notify"],
			addressingMode: group.attrs["addressing_mode"] == "lid" ? .lid : .pn,
			owner: JID(group.attrs["creator"])?.normalizedUser,
			ownerPn: JID(group.attrs["creator_pn"])?.normalizedUser,
			ownerUsername: group.attrs["creator_username"],
			ownerCountryCode: group.attrs["creator_country_code"],
			subject: group.attrs["subject"] ?? "",
			subjectOwner: group.attrs["s_o"],
			subjectOwnerPn: group.attrs["s_o_pn"],
			subjectOwnerUsername: group.attrs["s_o_username"],
			subjectTime: group.attrs["s_t"].flatMap(Int64.init),
			creation: group.attrs["creation"].flatMap(Int64.init),
			desc: descNode?.childString(named: "body"),
			descOwner: JID(descNode?.attrs["participant"])?.normalizedUser,
			descOwnerPn: JID(descNode?.attrs["participant_pn"])?.normalizedUser,
			descOwnerUsername: descNode?.attrs["participant_username"],
			descId: descNode?.attrs["id"],
			descTime: descNode?.attrs["t"].flatMap(Int64.init),
			linkedParent: group.firstChild(named: "linked_parent")?.attrs["jid"],
			restrict: group.firstChild(named: "locked") != nil,
			announce: group.firstChild(named: "announcement") != nil,
			memberAddMode: group.childString(named: "member_add_mode") == "all_member_add",
			joinApprovalMode: group.firstChild(named: "membership_approval_mode") != nil,
			isCommunity: group.firstChild(named: "parent") != nil,
			isCommunityAnnounce: group.firstChild(named: defaultSubGroupTag) != nil,
			size: group.attrs["size"].flatMap(Int.init) ?? participants.count,
			participants: participants,
			ephemeralDuration: group.firstChild(named: "ephemeral")?.attrs["expiration"].flatMap(Int64.init)
		)
	}
}
