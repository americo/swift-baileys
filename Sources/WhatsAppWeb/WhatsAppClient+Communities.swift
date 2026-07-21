import Foundation

extension WhatsAppClient {
	public func communityMetadata(_ jid: String, requestID: String? = nil) async throws -> GroupMetadata {
		let result = try await communityQuery(
			to: jid,
			type: "get",
			content: [BinaryNode(tag: "query", attrs: ["request": "interactive"])],
			requestID: requestID
		)
		return try GroupMetadataParser.parseCommunity(result)
	}

	public func communityFetchAllParticipating(requestID: String? = nil) async throws -> [String: GroupMetadata] {
		let result = try await communityQuery(
			to: "@g.us",
			type: "get",
			content: [
				BinaryNode(tag: "participating", content: .nodes([
					BinaryNode(tag: "participants"),
					BinaryNode(tag: "description")
				]))
			],
			requestID: requestID
		)
		var communities: [String: GroupMetadata] = [:]
		for community in result.firstChild(named: "communities")?.children(named: "community") ?? [] {
			let metadata = try GroupMetadataParser.parseCommunity(BinaryNode(tag: "result", content: .nodes([community])))
			communities[metadata.id] = metadata
		}
		return communities
	}

	public func communityCreate(
		subject: String,
		description: String = "",
		requestID: String? = nil
	) async throws -> GroupMetadata {
		let descriptionID = String(
			try messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id).prefix(12)
		)
		let result = try await communityQuery(
			to: "@g.us",
			type: "set",
			content: [
				BinaryNode(
					tag: "create",
					attrs: ["subject": subject],
					content: .nodes([
						BinaryNode(
							tag: "description",
							attrs: ["id": descriptionID],
							content: .nodes([
								BinaryNode(tag: "body", content: .data(Data(description.utf8)))
							])
						),
						BinaryNode(tag: "parent", attrs: ["default_membership_approval_mode": "request_required"]),
						BinaryNode(tag: "allow_non_admin_sub_group_creation"),
						BinaryNode(tag: "create_general_chat")
					])
				)
			],
			requestID: requestID
		)
		return try await metadataFromCreatedGroupResult(result)
	}

	public func communityCreate(
		_ subject: String,
		_ description: String = "",
		requestID: String? = nil
	) async throws -> GroupMetadata {
		try await communityCreate(subject: subject, description: description, requestID: requestID)
	}

	public func communityCreateGroup(
		subject: String,
		participants: [String],
		parentCommunityJID: String,
		requestID: String? = nil,
		groupKey: String? = nil
	) async throws -> GroupMetadata {
		let key = try groupKey ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let result = try await communityQuery(
			to: "@g.us",
			type: "set",
			content: [
				BinaryNode(
					tag: "create",
					attrs: ["subject": subject, "key": key],
					content: .nodes(
						participants.map { BinaryNode(tag: "participant", attrs: ["jid": $0]) } + [
							BinaryNode(tag: "linked_parent", attrs: ["jid": parentCommunityJID])
						]
					)
				)
			],
			requestID: requestID
		)
		return try await metadataFromCreatedGroupResult(result)
	}

	public func communityCreateGroup(
		_ subject: String,
		_ participants: [String],
		_ parentCommunityJID: String,
		requestID: String? = nil,
		groupKey: String? = nil
	) async throws -> GroupMetadata {
		try await communityCreateGroup(
			subject: subject,
			participants: participants,
			parentCommunityJID: parentCommunityJID,
			requestID: requestID,
			groupKey: groupKey
		)
	}

	public func communityFetchLinkedGroups(
		_ jid: String,
		requestID: String? = nil
	) async throws -> CommunityLinkedGroups {
		let metadata = try await groupMetadata(jid)
		let communityJID = metadata.linkedParent ?? jid
		let result = try await communityQuery(
			to: communityJID,
			type: "get",
			content: [BinaryNode(tag: "sub_groups")],
			requestID: requestID
		)
		let linkedGroups = result.firstChild(named: "sub_groups")?.children(named: "group").map {
			CommunityLinkedGroup(
				id: $0.attrs["id"].map { JID.encode(user: $0, server: JIDServer.group.rawValue) },
				subject: $0.attrs["subject"] ?? "",
				creation: $0.attrs["creation"].flatMap(Int64.init),
				owner: JID($0.attrs["creator"])?.normalizedUser,
				size: $0.attrs["size"].flatMap(Int.init)
			)
		} ?? []

		return CommunityLinkedGroups(
			communityJID: communityJID,
			isCommunity: metadata.linkedParent == nil,
			linkedGroups: linkedGroups
		)
	}

	public func communityLeave(_ jid: String, requestID: String? = nil) async throws {
		_ = try await communityQuery(
			to: "@g.us",
			type: "set",
			content: [
				BinaryNode(
					tag: "leave",
					content: .nodes([
						BinaryNode(tag: "community", attrs: ["id": jid])
					])
				)
			],
			requestID: requestID
		)
	}

	public func communityUpdateSubject(_ jid: String, subject: String, requestID: String? = nil) async throws {
		_ = try await communityQuery(
			to: jid,
			type: "set",
			content: [
				BinaryNode(tag: "subject", content: .data(Data(subject.utf8)))
			],
			requestID: requestID
		)
	}

	public func communityUpdateSubject(_ jid: String, _ subject: String, requestID: String? = nil) async throws {
		try await communityUpdateSubject(jid, subject: subject, requestID: requestID)
	}

	public func communityUpdateDescription(
		_ jid: String,
		description: String?,
		requestID: String? = nil
	) async throws {
		let metadata = try await communityMetadata(jid)
		var attrs: [(String, String)] = []
		if let description {
			attrs.append(("id", try messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)))
			if let descID = metadata.descId {
				attrs.append(("prev", descID))
			}

			_ = try await communityQuery(
				to: jid,
				type: "set",
				content: [
					BinaryNode(
						tag: "description",
						attrs: BinaryNodeAttributes(attrs),
						content: .nodes([
							BinaryNode(tag: "body", content: .data(Data(description.utf8)))
						])
					)
				],
				requestID: requestID
			)
		} else {
			attrs.append(("delete", "true"))
			if let descID = metadata.descId {
				attrs.append(("prev", descID))
			}

			_ = try await communityQuery(
				to: jid,
				type: "set",
				content: [BinaryNode(tag: "description", attrs: BinaryNodeAttributes(attrs))],
				requestID: requestID
			)
		}
	}

	public func communityLinkGroup(
		groupJID: String,
		parentCommunityJID: String,
		requestID: String? = nil
	) async throws {
		_ = try await communityQuery(
			to: parentCommunityJID,
			type: "set",
			content: [
				BinaryNode(tag: "links", content: .nodes([
					BinaryNode(
						tag: "link",
						attrs: ["link_type": "sub_group"],
						content: .nodes([
							BinaryNode(tag: "group", attrs: ["jid": groupJID])
						])
					)
				]))
			],
			requestID: requestID
		)
	}

	public func communityLinkGroup(_ groupJID: String, _ parentCommunityJID: String, requestID: String? = nil) async throws {
		try await communityLinkGroup(groupJID: groupJID, parentCommunityJID: parentCommunityJID, requestID: requestID)
	}

	public func communityUnlinkGroup(
		groupJID: String,
		parentCommunityJID: String,
		requestID: String? = nil
	) async throws {
		_ = try await communityQuery(
			to: parentCommunityJID,
			type: "set",
			content: [
				BinaryNode(
					tag: "unlink",
					attrs: ["unlink_type": "sub_group"],
					content: .nodes([
						BinaryNode(tag: "group", attrs: ["jid": groupJID])
					])
				)
			],
			requestID: requestID
		)
	}

	public func communityUnlinkGroup(_ groupJID: String, _ parentCommunityJID: String, requestID: String? = nil) async throws {
		try await communityUnlinkGroup(groupJID: groupJID, parentCommunityJID: parentCommunityJID, requestID: requestID)
	}

	public func communityParticipantsUpdate(
		_ jid: String,
		participants: [String],
		action: GroupParticipantAction,
		requestID: String? = nil
	) async throws -> [GroupParticipantUpdateResult] {
		let result = try await communityQuery(
			to: jid,
			type: "set",
			content: [
				BinaryNode(
					tag: action.rawValue,
					attrs: action == .remove ? ["linked_groups": "true"] : [:],
					content: .nodes(participants.map { BinaryNode(tag: "participant", attrs: ["jid": $0]) })
				)
			],
			requestID: requestID
		)
		return result.firstChild(named: action.rawValue)?.children(named: "participant").map {
			GroupParticipantUpdateResult(jid: $0.attrs["jid"] ?? "", status: $0.attrs["error"] ?? "200", content: $0)
		} ?? []
	}

	public func communityRequestParticipantsList(
		_ jid: String,
		requestID: String? = nil
	) async throws -> [GroupMembershipApprovalRequest] {
		let result = try await communityQuery(
			to: jid,
			type: "get",
			content: [BinaryNode(tag: "membership_approval_requests")],
			requestID: requestID
		)
		return result.firstChild(named: "membership_approval_requests")?
			.children(named: "membership_approval_request")
			.map {
				GroupMembershipApprovalRequest(
					jid: $0.attrs["jid"] ?? "",
					requestMethod: $0.attrs["request_method"],
					requestedAt: $0.attrs["t"].flatMap(Int64.init)
				)
			} ?? []
	}

	public func communityRequestParticipantsUpdate(
		_ jid: String,
		participants: [String],
		action: GroupMembershipApprovalAction,
		requestID: String? = nil
	) async throws -> [GroupParticipantUpdateResult] {
		let result = try await communityQuery(
			to: jid,
			type: "set",
			content: [
				BinaryNode(
					tag: "membership_requests_action",
					content: .nodes([
						BinaryNode(
							tag: action.rawValue,
							content: .nodes(participants.map { BinaryNode(tag: "participant", attrs: ["jid": $0]) })
						)
					])
				)
			],
			requestID: requestID
		)
		return result.firstChild(named: "membership_requests_action")?
			.firstChild(named: action.rawValue)?
			.children(named: "participant")
			.map { GroupParticipantUpdateResult(jid: $0.attrs["jid"] ?? "", status: $0.attrs["error"] ?? "200") } ?? []
	}

	public func communityInviteCode(_ jid: String, requestID: String? = nil) async throws -> String? {
		let result = try await communityQuery(
			to: jid,
			type: "get",
			content: [BinaryNode(tag: "invite")],
			requestID: requestID
		)
		return result.firstChild(named: "invite")?.attrs["code"]
	}

	public func communityRevokeInvite(_ jid: String, requestID: String? = nil) async throws -> String? {
		let result = try await communityQuery(
			to: jid,
			type: "set",
			content: [BinaryNode(tag: "invite")],
			requestID: requestID
		)
		return result.firstChild(named: "invite")?.attrs["code"]
	}

	public func communityAcceptInvite(code: String, requestID: String? = nil) async throws -> String? {
		let result = try await communityQuery(
			to: "@g.us",
			type: "set",
			content: [BinaryNode(tag: "invite", attrs: ["code": code])],
			requestID: requestID
		)
		return result.firstChild(named: "community")?.attrs["jid"]
	}

	public func communityAcceptInvite(_ code: String, requestID: String? = nil) async throws -> String? {
		try await communityAcceptInvite(code: code, requestID: requestID)
	}

	public func communityGetInviteInfo(code: String, requestID: String? = nil) async throws -> GroupMetadata {
		let result = try await communityQuery(
			to: "@g.us",
			type: "get",
			content: [BinaryNode(tag: "invite", attrs: ["code": code])],
			requestID: requestID
		)
		return try GroupMetadataParser.parseCommunity(result)
	}

	public func communityGetInviteInfo(_ code: String, requestID: String? = nil) async throws -> GroupMetadata {
		try await communityGetInviteInfo(code: code, requestID: requestID)
	}

	public func communityRevokeInviteV4(
		communityJID: String,
		invitedJID: String,
		requestID: String? = nil
	) async throws -> Bool {
		_ = try await communityQuery(
			to: communityJID,
			type: "set",
			content: [
				BinaryNode(
					tag: "revoke",
					content: .nodes([
						BinaryNode(tag: "participant", attrs: ["jid": invitedJID])
					])
				)
			],
			requestID: requestID
		)
		return true
	}

	public func communityRevokeInviteV4(
		_ communityJID: String,
		_ invitedJID: String,
		requestID: String? = nil
	) async throws -> Bool {
		try await communityRevokeInviteV4(communityJID: communityJID, invitedJID: invitedJID, requestID: requestID)
	}

	public func communityAcceptInviteV4(
		groupJID: String,
		inviteCode: String,
		inviteExpiration: Int64,
		adminJID: String,
		requestID: String? = nil
	) async throws -> String? {
		let result = try await communityQuery(
			to: groupJID,
			type: "set",
			content: [
				BinaryNode(
					tag: "accept",
					attrs: [
						"code": inviteCode,
						"expiration": String(inviteExpiration),
						"admin": adminJID
					]
				)
			],
			requestID: requestID
		)
		return result.attrs["from"]
	}

	public func communityToggleEphemeral(
		_ jid: String,
		expirationSeconds: Int,
		requestID: String? = nil
	) async throws {
		_ = try await communityQuery(
			to: jid,
			type: "set",
			content: [
				expirationSeconds > 0
					? BinaryNode(tag: "ephemeral", attrs: ["expiration": String(expirationSeconds)])
					: BinaryNode(tag: "not_ephemeral")
			],
			requestID: requestID
		)
	}

	public func communityToggleEphemeral(_ jid: String, _ expirationSeconds: Int, requestID: String? = nil) async throws {
		try await communityToggleEphemeral(jid, expirationSeconds: expirationSeconds, requestID: requestID)
	}

	public func communitySettingUpdate(
		_ jid: String,
		setting: GroupSetting,
		requestID: String? = nil
	) async throws {
		_ = try await communityQuery(
			to: jid,
			type: "set",
			content: [BinaryNode(tag: setting.rawValue)],
			requestID: requestID
		)
	}

	public func communitySettingUpdate(_ jid: String, _ setting: GroupSetting, requestID: String? = nil) async throws {
		try await communitySettingUpdate(jid, setting: setting, requestID: requestID)
	}

	public func communityMemberAddMode(
		_ jid: String,
		mode: GroupMemberAddMode,
		requestID: String? = nil
	) async throws {
		_ = try await communityQuery(
			to: jid,
			type: "set",
			content: [BinaryNode(tag: "member_add_mode", content: .string(mode.rawValue))],
			requestID: requestID
		)
	}

	public func communityMemberAddMode(_ jid: String, _ mode: GroupMemberAddMode, requestID: String? = nil) async throws {
		try await communityMemberAddMode(jid, mode: mode, requestID: requestID)
	}

	public func communityJoinApprovalMode(
		_ jid: String,
		mode: GroupJoinApprovalMode,
		requestID: String? = nil
	) async throws {
		_ = try await communityQuery(
			to: jid,
			type: "set",
			content: [
				BinaryNode(tag: "membership_approval_mode", content: .nodes([
					BinaryNode(tag: "community_join", attrs: ["state": mode.rawValue])
				]))
			],
			requestID: requestID
		)
	}

	public func communityJoinApprovalMode(_ jid: String, _ mode: GroupJoinApprovalMode, requestID: String? = nil) async throws {
		try await communityJoinApprovalMode(jid, mode: mode, requestID: requestID)
	}

	private func metadataFromCreatedGroupResult(_ result: BinaryNode) async throws -> GroupMetadata {
		guard let group = result.firstChild(named: "group") else {
			throw GroupMetadataParserError.missingGroupNode
		}

		guard let groupID = group.attrs["id"] else {
			throw GroupMetadataParserError.missingGroupID
		}

		return try await groupMetadata(JID.encode(user: groupID, server: JIDServer.group.rawValue))
	}

	private func communityQuery(
		to jid: String,
		type: String,
		content: [BinaryNode],
		requestID: String?
	) async throws -> BinaryNode {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		return try await query(
			BinaryNode(
				tag: "iq",
				attrs: [
					"id": id,
					"to": jid,
					"type": type,
					"xmlns": "w:g2"
				],
				content: .nodes(content)
			)
		)
	}
}
