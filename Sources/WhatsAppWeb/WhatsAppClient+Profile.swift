import Foundation

public enum ProfilePictureType: String, Sendable {
	case preview
	case image
}

public enum CallLinkType: String, Sendable {
	case audio
	case video
}

public enum BlockStatusAction: String, Sendable {
	case block
	case unblock
}

public enum PrivacySettingValue: String, Sendable {
	case all
	case contacts
	case contactBlacklist = "contact_blacklist"
	case none
}

public enum OnlinePrivacySettingValue: String, Sendable {
	case all
	case matchLastSeen = "match_last_seen"
}

public enum GroupAddPrivacySettingValue: String, Sendable {
	case all
	case contacts
	case contactBlacklist = "contact_blacklist"
}

public enum CallPrivacySettingValue: String, Sendable {
	case all
	case known
}

public enum MessagesPrivacySettingValue: String, Sendable {
	case all
	case contacts
}

public enum ReadReceiptsPrivacySettingValue: String, Sendable {
	case all
	case none
}

extension WhatsAppClient {
	public func profilePictureURL(
		for jid: String,
		type: ProfilePictureType = .preview,
		requestID: String? = nil
	) async throws -> String? {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let normalizedJID = JID(jid)?.normalizedUser ?? jid
		var content = [
			BinaryNode(tag: "picture", attrs: ["type": type.rawValue, "query": "url"])
		]
		let me = authenticationState?.credentials.me
		let isSelf = JID.areSameUser(normalizedJID, me?.id) || JID.areSameUser(normalizedJID, me?.lid)
		if serverProps.profilePicturePrivacyToken,
		   !isSelf,
		   let tokenNode = await TrustedContactTokenNodeBuilder.build(for: normalizedJID, keys: authenticationState?.keys) {
			content.append(tokenNode)
		}

		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"target": normalizedJID,
				"to": "@s.whatsapp.net",
				"type": "get",
				"xmlns": "w:profile:picture"
			],
			content: .nodes(content)
		))
		return result.firstChild(named: "picture")?.attrs["url"]
	}

	public func profilePictureUrl(
		for jid: String,
		type: ProfilePictureType = .preview,
		requestID: String? = nil
	) async throws -> String? {
		try await profilePictureURL(for: jid, type: type, requestID: requestID)
	}

	public func updateProfilePicture(
		for jid: String,
		imageData: Data,
		requestID: String? = nil
	) async throws {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		var attrs: [(String, String)] = [
			("id", id),
			("to", "@s.whatsapp.net"),
			("type", "set"),
			("xmlns", "w:profile:picture")
		]
		if let target = profilePictureTargetJID(for: jid) {
			attrs.append(("target", target))
		}

		_ = try await query(BinaryNode(
			tag: "iq",
			attrs: BinaryNodeAttributes(attrs),
			content: .nodes([
				BinaryNode(tag: "picture", attrs: ["type": "image"], content: .data(imageData))
			])
		))
	}

	public func removeProfilePicture(for jid: String, requestID: String? = nil) async throws {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		var attrs: [(String, String)] = [
			("id", id),
			("to", "@s.whatsapp.net"),
			("type", "set"),
			("xmlns", "w:profile:picture")
		]
		if let target = profilePictureTargetJID(for: jid) {
			attrs.append(("target", target))
		}

		_ = try await query(BinaryNode(tag: "iq", attrs: BinaryNodeAttributes(attrs)))
	}

	public func updateProfileStatus(_ status: String, requestID: String? = nil) async throws {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		_ = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"to": "@s.whatsapp.net",
				"type": "set",
				"xmlns": "status"
			],
			content: .nodes([
				BinaryNode(tag: "status", content: .data(Data(status.utf8)))
			])
		))
	}

	public func fetchBlocklist(requestID: String? = nil) async throws -> [String] {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"xmlns": "blocklist",
				"to": "@s.whatsapp.net",
				"type": "get"
			]
		))
		return result.firstChild(named: "list")?.children(named: "item").compactMap { $0.attrs["jid"] } ?? []
	}

	public func updateBlockStatus(
		for jid: String,
		action: BlockStatusAction,
		requestID: String? = nil
	) async throws {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		guard let keys = authenticationState?.keys else {
			throw WhatsAppClientError.missingAuthenticationState
		}

		let normalizedJID = JID(jid)?.normalizedUser ?? jid
		let lid: String
		let pnJID: String?
		if normalizedJID.isLIDUserJID || normalizedJID.isHostedLIDUserJID {
			lid = normalizedJID
			if action == .block {
				guard let pn = try await LIDMappingStore.phoneNumber(for: normalizedJID, in: keys) else {
					throw WhatsAppClientError.missingPNMappingForLID(normalizedJID)
				}
				pnJID = JID(pn)?.normalizedUser ?? pn
			} else {
				pnJID = nil
			}
		} else if normalizedJID.isWhatsAppUserJID || normalizedJID.isHostedUserJID {
			guard let mappedLID = try await LIDMappingStore.lid(for: normalizedJID, in: keys) else {
				throw WhatsAppClientError.missingLIDMappingForPN(normalizedJID)
			}
			lid = mappedLID
			pnJID = action == .block ? normalizedJID : nil
		} else {
			throw WhatsAppClientError.invalidBlocklistJID(jid)
		}

		var itemAttrs: [(String, String)] = [
			("action", action.rawValue),
			("jid", lid)
		]
		if let pnJID {
			itemAttrs.append(("pn_jid", pnJID))
		}

		_ = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"xmlns": "blocklist",
				"to": "@s.whatsapp.net",
				"type": "set"
			],
			content: .nodes([
				BinaryNode(tag: "item", attrs: BinaryNodeAttributes(itemAttrs))
			])
		))
	}

	public func fetchPrivacySettings(requestID: String? = nil) async throws -> [String: String] {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"xmlns": "privacy",
				"to": "@s.whatsapp.net",
				"type": "get"
			],
			content: .nodes([
				BinaryNode(tag: "privacy")
			])
		))

		return Dictionary(uniqueKeysWithValues: result.firstChild(named: "privacy")?.children(named: "category").compactMap { category in
			guard let name = category.attrs["name"], let value = category.attrs["value"] else {
				return nil
			}

			return (name, value)
		} ?? [])
	}

	public func updateMessagesPrivacy(_ value: MessagesPrivacySettingValue, requestID: String? = nil) async throws {
		try await updatePrivacySetting(name: "messages", value: value.rawValue, requestID: requestID)
	}

	public func updateCallPrivacy(_ value: CallPrivacySettingValue, requestID: String? = nil) async throws {
		try await updatePrivacySetting(name: "calladd", value: value.rawValue, requestID: requestID)
	}

	public func updateLastSeenPrivacy(_ value: PrivacySettingValue, requestID: String? = nil) async throws {
		try await updatePrivacySetting(name: "last", value: value.rawValue, requestID: requestID)
	}

	public func updateOnlinePrivacy(_ value: OnlinePrivacySettingValue, requestID: String? = nil) async throws {
		try await updatePrivacySetting(name: "online", value: value.rawValue, requestID: requestID)
	}

	public func updateProfilePicturePrivacy(_ value: PrivacySettingValue, requestID: String? = nil) async throws {
		try await updatePrivacySetting(name: "profile", value: value.rawValue, requestID: requestID)
	}

	public func updateStatusPrivacy(_ value: PrivacySettingValue, requestID: String? = nil) async throws {
		try await updatePrivacySetting(name: "status", value: value.rawValue, requestID: requestID)
	}

	public func updateReadReceiptsPrivacy(_ value: ReadReceiptsPrivacySettingValue, requestID: String? = nil) async throws {
		try await updatePrivacySetting(name: "readreceipts", value: value.rawValue, requestID: requestID)
	}

	public func updateGroupsAddPrivacy(_ value: GroupAddPrivacySettingValue, requestID: String? = nil) async throws {
		try await updatePrivacySetting(name: "groupadd", value: value.rawValue, requestID: requestID)
	}

	public func createCallLink(
		type: CallLinkType,
		eventStartTime: Int64? = nil,
		requestID: String? = nil
	) async throws -> String? {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let linkCreateContent: BinaryNode.Content? = eventStartTime.map {
			.nodes([
				BinaryNode(tag: "event", attrs: ["start_time": String($0)])
			])
		}
		let result = try await query(BinaryNode(
			tag: "call",
			attrs: ["id": id, "to": "@call"],
			content: .nodes([
				BinaryNode(
					tag: "link_create",
					attrs: ["media": type.rawValue],
					content: linkCreateContent
				)
			])
		))
		return result.firstChild(named: "link_create")?.attrs["token"]
	}

	private func profilePictureTargetJID(for jid: String) -> String? {
		let normalizedJID = JID(jid)?.normalizedUser ?? jid
		guard let me = authenticationState?.credentials.me else {
			return normalizedJID
		}

		if JID.areSameUser(normalizedJID, me.id) || JID.areSameUser(normalizedJID, me.lid) {
			return nil
		}

		return normalizedJID
	}

	private func updatePrivacySetting(name: String, value: String, requestID: String?) async throws {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		_ = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"xmlns": "privacy",
				"to": "@s.whatsapp.net",
				"type": "set"
			],
			content: .nodes([
				BinaryNode(tag: "privacy", content: .nodes([
					BinaryNode(tag: "category", attrs: ["name": name, "value": value])
				]))
			])
		))
	}

}
