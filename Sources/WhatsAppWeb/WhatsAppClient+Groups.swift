import Foundation

extension WhatsAppClient {
	public func groupMetadata(_ jid: String, requestID: String? = nil) async throws -> GroupMetadata {
		let result = try await groupQuery(
			to: jid,
			type: "get",
			content: [BinaryNode(tag: "query", attrs: ["request": "interactive"])],
			requestID: requestID
		)
		return try GroupMetadataParser.parse(result)
	}

	public func groupFetchAllParticipating(requestID: String? = nil) async throws -> [String: GroupMetadata] {
		let result = try await groupQuery(
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
		var groups: [String: GroupMetadata] = [:]
		for group in result.firstChild(named: "groups")?.children(named: "group") ?? [] {
			let metadata = try GroupMetadataParser.parse(BinaryNode(tag: "result", content: .nodes([group])))
			groups[metadata.id] = metadata
		}
		return groups
	}

	public func groupCreate(
		subject: String,
		participants: [String],
		requestID: String? = nil,
		groupKey: String? = nil
	) async throws -> GroupMetadata {
		let key = try groupKey ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let result = try await groupQuery(
			to: "@g.us",
			type: "set",
			content: [
				BinaryNode(
					tag: "create",
					attrs: ["subject": subject, "key": key],
					content: .nodes(participants.map { BinaryNode(tag: "participant", attrs: ["jid": $0]) })
				)
			],
			requestID: requestID
		)
		return try GroupMetadataParser.parse(result)
	}

	public func groupCreate(
		_ subject: String,
		_ participants: [String],
		requestID: String? = nil,
		groupKey: String? = nil
	) async throws -> GroupMetadata {
		try await groupCreate(subject: subject, participants: participants, requestID: requestID, groupKey: groupKey)
	}

	public func groupLeave(_ jid: String, requestID: String? = nil) async throws {
		_ = try await groupQuery(
			to: "@g.us",
			type: "set",
			content: [
				BinaryNode(
					tag: "leave",
					content: .nodes([
						BinaryNode(tag: "group", attrs: ["id": jid])
					])
				)
			],
			requestID: requestID
		)
	}

	public func groupParticipantsUpdate(
		_ jid: String,
		participants: [String],
		action: GroupParticipantAction,
		requestID: String? = nil
	) async throws -> [GroupParticipantUpdateResult] {
		let result = try await groupQuery(
			to: jid,
			type: "set",
			content: [
				BinaryNode(
					tag: action.rawValue,
					content: .nodes(participants.map { BinaryNode(tag: "participant", attrs: ["jid": $0]) })
				)
			],
			requestID: requestID
		)
		return result.firstChild(named: action.rawValue)?.children(named: "participant").map {
			GroupParticipantUpdateResult(jid: $0.attrs["jid"] ?? "", status: $0.attrs["error"] ?? "200", content: $0)
		} ?? []
	}

	public func groupRequestParticipantsList(
		_ jid: String,
		requestID: String? = nil
	) async throws -> [GroupMembershipApprovalRequest] {
		let result = try await groupQuery(
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

	public func groupRequestParticipantsUpdate(
		_ jid: String,
		participants: [String],
		action: GroupMembershipApprovalAction,
		requestID: String? = nil
	) async throws -> [GroupParticipantUpdateResult] {
		let result = try await groupQuery(
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

	public func groupUpdateSubject(_ jid: String, subject: String, requestID: String? = nil) async throws {
		_ = try await groupQuery(
			to: jid,
			type: "set",
			content: [
				BinaryNode(tag: "subject", content: .data(Data(subject.utf8)))
			],
			requestID: requestID
		)
	}

	public func groupUpdateSubject(_ jid: String, _ subject: String, requestID: String? = nil) async throws {
		try await groupUpdateSubject(jid, subject: subject, requestID: requestID)
	}

	public func groupUpdateDescription(
		_ jid: String,
		description: String?,
		requestID: String? = nil
	) async throws {
		let metadata = try await groupMetadata(jid)
		var attrs: [(String, String)] = []
		if let description {
			attrs.append(("id", try messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)))
			if let descID = metadata.descId {
				attrs.append(("prev", descID))
			}

			_ = try await groupQuery(
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

			_ = try await groupQuery(
				to: jid,
				type: "set",
				content: [BinaryNode(tag: "description", attrs: BinaryNodeAttributes(attrs))],
				requestID: requestID
			)
		}
	}

	public func groupToggleEphemeral(
		_ jid: String,
		expirationSeconds: Int,
		requestID: String? = nil
	) async throws {
		_ = try await groupQuery(
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

	public func groupToggleEphemeral(_ jid: String, _ expirationSeconds: Int, requestID: String? = nil) async throws {
		try await groupToggleEphemeral(jid, expirationSeconds: expirationSeconds, requestID: requestID)
	}

	public func groupSettingUpdate(
		_ jid: String,
		setting: GroupSetting,
		requestID: String? = nil
	) async throws {
		_ = try await groupQuery(
			to: jid,
			type: "set",
			content: [BinaryNode(tag: setting.rawValue)],
			requestID: requestID
		)
	}

	public func groupSettingUpdate(_ jid: String, _ setting: GroupSetting, requestID: String? = nil) async throws {
		try await groupSettingUpdate(jid, setting: setting, requestID: requestID)
	}

	public func groupMemberAddMode(
		_ jid: String,
		mode: GroupMemberAddMode,
		requestID: String? = nil
	) async throws {
		_ = try await groupQuery(
			to: jid,
			type: "set",
			content: [BinaryNode(tag: "member_add_mode", content: .string(mode.rawValue))],
			requestID: requestID
		)
	}

	public func groupMemberAddMode(_ jid: String, _ mode: GroupMemberAddMode, requestID: String? = nil) async throws {
		try await groupMemberAddMode(jid, mode: mode, requestID: requestID)
	}

	public func groupJoinApprovalMode(
		_ jid: String,
		mode: GroupJoinApprovalMode,
		requestID: String? = nil
	) async throws {
		_ = try await groupQuery(
			to: jid,
			type: "set",
			content: [
				BinaryNode(
					tag: "membership_approval_mode",
					content: .nodes([
						BinaryNode(tag: "group_join", attrs: ["state": mode.rawValue])
					])
				)
			],
			requestID: requestID
		)
	}

	public func groupJoinApprovalMode(_ jid: String, _ mode: GroupJoinApprovalMode, requestID: String? = nil) async throws {
		try await groupJoinApprovalMode(jid, mode: mode, requestID: requestID)
	}

	public func groupInviteCode(_ jid: String, requestID: String? = nil) async throws -> String? {
		let result = try await groupQuery(
			to: jid,
			type: "get",
			content: [BinaryNode(tag: "invite")],
			requestID: requestID
		)
		return result.firstChild(named: "invite")?.attrs["code"]
	}

	public func groupRevokeInvite(_ jid: String, requestID: String? = nil) async throws -> String? {
		let result = try await groupQuery(
			to: jid,
			type: "set",
			content: [BinaryNode(tag: "invite")],
			requestID: requestID
		)
		return result.firstChild(named: "invite")?.attrs["code"]
	}

	public func groupAcceptInvite(code: String, requestID: String? = nil) async throws -> String? {
		let result = try await groupQuery(
			to: "@g.us",
			type: "set",
			content: [BinaryNode(tag: "invite", attrs: ["code": code])],
			requestID: requestID
		)
		return result.firstChild(named: "group")?.attrs["jid"]
	}

	public func groupAcceptInvite(_ code: String, requestID: String? = nil) async throws -> String? {
		try await groupAcceptInvite(code: code, requestID: requestID)
	}

	public func groupGetInviteInfo(code: String, requestID: String? = nil) async throws -> GroupMetadata {
		let result = try await groupQuery(
			to: "@g.us",
			type: "get",
			content: [BinaryNode(tag: "invite", attrs: ["code": code])],
			requestID: requestID
		)
		return try GroupMetadataParser.parse(result)
	}

	public func groupGetInviteInfo(_ code: String, requestID: String? = nil) async throws -> GroupMetadata {
		try await groupGetInviteInfo(code: code, requestID: requestID)
	}

	public func groupRevokeInviteV4(
		groupJID: String,
		invitedJID: String,
		requestID: String? = nil
	) async throws -> Bool {
		_ = try await groupQuery(
			to: groupJID,
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

	public func groupRevokeInviteV4(
		_ groupJID: String,
		_ invitedJID: String,
		requestID: String? = nil
	) async throws -> Bool {
		try await groupRevokeInviteV4(groupJID: groupJID, invitedJID: invitedJID, requestID: requestID)
	}

	public func groupAcceptInviteV4(
		groupJID: String,
		inviteCode: String,
		inviteExpiration: Int64,
		adminJID: String,
		requestID: String? = nil
	) async throws -> String? {
		let result = try await groupQuery(
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

	private func groupQuery(
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
