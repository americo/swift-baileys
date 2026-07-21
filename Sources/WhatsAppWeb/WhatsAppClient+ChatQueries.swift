import Foundation

public enum DirtyBitsType: String, Sendable {
	case accountSync = "account_sync"
	case groups
}

public struct ContactStatus: Equatable, Sendable {
	public let jid: String
	public let status: String?
	public let setAt: Date?

	public init(jid: String, status: String?, setAt: Date?) {
		self.jid = jid
		self.status = status
		self.setAt = setAt
	}
}

public struct ContactDisappearingDuration: Equatable, Sendable {
	public let jid: String
	public let duration: Int
	public let setAt: Date?

	public init(jid: String, duration: Int, setAt: Date?) {
		self.jid = jid
		self.duration = duration
		self.setAt = setAt
	}
}

public struct BotListInfo: Equatable, Sendable {
	public let jid: String
	public let personaId: String

	public init(jid: String, personaId: String) {
		self.jid = jid
		self.personaId = personaId
	}
}

public struct OnWhatsAppResult: Equatable, Sendable {
	public let jid: String
	public let exists: Bool

	public init(jid: String, exists: Bool) {
		self.jid = jid
		self.exists = exists
	}
}

public struct LIDMapping: Equatable, Sendable {
	public let pn: String
	public let lid: String

	public init(pn: String, lid: String) {
		self.pn = pn
		self.lid = lid
	}
}

extension WhatsAppClient {
	public func updateDefaultDisappearingMode(duration: Int, requestID: String? = nil) async throws {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		_ = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"xmlns": "disappearing_mode",
				"to": "@s.whatsapp.net",
				"type": "set"
			],
			content: .nodes([
				BinaryNode(tag: "disappearing_mode", attrs: ["duration": String(duration)])
			])
		))
	}

	public func botListV2(requestID: String? = nil) async throws -> [BotListInfo] {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"xmlns": "bot",
				"to": "@s.whatsapp.net",
				"type": "get"
			],
			content: .nodes([
				BinaryNode(tag: "bot", attrs: ["v": "2"])
			])
		))
		return result.firstChild(named: "bot")?
			.children(named: "section")
			.filter { $0.attrs["type"] == "all" }
			.flatMap { $0.children(named: "bot") }
			.compactMap { bot in
				guard let jid = bot.attrs["jid"], let personaId = bot.attrs["persona_id"] else {
					return nil
				}

				return BotListInfo(jid: jid, personaId: personaId)
			} ?? []
	}

	public func getBotListV2(requestID: String? = nil) async throws -> [BotListInfo] {
		try await botListV2(requestID: requestID)
	}

	public func cleanDirtyBits(
		_ type: DirtyBitsType,
		fromTimestamp: Int? = nil,
		requestID: String? = nil
	) async throws {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		var cleanAttrs: [(String, String)] = [("type", type.rawValue)]
		if let fromTimestamp {
			cleanAttrs.append(("timestamp", String(fromTimestamp)))
		}

		try await sendNode(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"xmlns": "urn:xmpp:whatsapp:dirty",
				"to": "@s.whatsapp.net",
				"type": "set"
			],
			content: .nodes([
				BinaryNode(tag: "clean", attrs: BinaryNodeAttributes(cleanAttrs))
			])
		))
	}

	public func onWhatsApp(_ phoneNumbers: [String], requestID: String? = nil) async throws -> [OnWhatsAppResult] {
		let phones = phoneNumbers.compactMap { value -> String? in
			if value.isLIDUserJID || value.isHostedLIDUserJID {
				return nil
			}

			let withoutPlus = value.replacingOccurrences(of: "+", with: "")
			let userPart = withoutPlus.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)[0]
			let phone = userPart.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)[0]
			return "+\(phone)"
		}
		guard !phones.isEmpty else {
			return []
		}

		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: ["id": id, "to": "@s.whatsapp.net", "type": "get", "xmlns": "usync"],
			content: .nodes([
				BinaryNode(
					tag: "usync",
					attrs: ["context": "interactive", "mode": "query", "sid": id, "last": "true", "index": "0"],
					content: .nodes([
						BinaryNode(tag: "query", content: .nodes([BinaryNode(tag: "contact")])),
						BinaryNode(
							tag: "list",
							content: .nodes(phones.map { phone in
								BinaryNode(
									tag: "user",
									content: .nodes([BinaryNode(tag: "contact", content: .string(phone))])
								)
							})
						)
					])
				)
			])
		))

		return result.firstChild(named: "usync")?
			.firstChild(named: "list")?
			.children(named: "user")
			.compactMap { user in
				guard let jid = user.attrs["jid"], let contactType = user.firstChild(named: "contact")?.attrs["type"] else {
					return nil
				}

				return OnWhatsAppResult(jid: jid, exists: contactType == "in")
			} ?? []
	}

	public func pnFromLIDUSync(_ jids: [String], requestID: String? = nil) async throws -> [LIDMapping] {
		let users: [String] = jids.compactMap { jid in
			if jid.isLIDUserJID || jid.isHostedLIDUserJID {
				return nil
			}

			return jid
		}
		guard !users.isEmpty else {
			return []
		}

		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: ["id": id, "to": "@s.whatsapp.net", "type": "get", "xmlns": "usync"],
			content: .nodes([
				BinaryNode(
					tag: "usync",
					attrs: ["context": "background", "mode": "query", "sid": id, "last": "true", "index": "0"],
					content: .nodes([
						BinaryNode(tag: "query", content: .nodes([BinaryNode(tag: "lid")])),
						BinaryNode(
							tag: "list",
							content: .nodes(users.map { jid in
								BinaryNode(tag: "user", attrs: ["jid": jid])
							})
						)
					])
				)
			])
		))

		return result.firstChild(named: "usync")?
			.firstChild(named: "list")?
			.children(named: "user")
			.compactMap { user in
				guard let pn = user.attrs["jid"], let lid = user.firstChild(named: "lid")?.attrs["val"] else {
					return nil
				}

				return LIDMapping(pn: pn, lid: lid)
			} ?? []
	}

	public func fetchProps(requestID: String? = nil) async throws -> [String: String] {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		var propsAttrs: [(String, String)] = [("protocol", "1")]
		if let hash = authenticationState?.credentials.lastPropertyHash {
			propsAttrs.append(("hash", hash))
		}

		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: ["id": id, "to": "@s.whatsapp.net", "type": "get", "xmlns": "abt"],
			content: .nodes([
				BinaryNode(tag: "props", attrs: BinaryNodeAttributes(propsAttrs))
			])
		))

		guard let props = result.firstChild(named: "props") else {
			return [:]
		}

		if let hash = props.attrs["hash"] {
			try await updateCredentials { credentials in
				credentials.lastPropertyHash = hash
			}
		}

		var parsedProps: [String: String] = [:]
		for prop in props.children(named: "prop") {
			let key = prop.attrs["name"] ?? prop.attrs["config_code"]
			let value = prop.attrs["value"] ?? prop.attrs["config_value"]
			guard let key, let value else {
				continue
			}

			parsedProps[key] = value
		}
		serverProps.apply(parsedProps)
		return parsedProps
	}

	public func fetchStatuses(
		for jids: [String],
		requestID: String? = nil
	) async throws -> [ContactStatus] {
		let result = try await query(makeUSyncRequest(
			for: jids,
			queryChild: BinaryNode(tag: "status"),
			requestID: requestID
		))
		return result.firstChild(named: "usync")?
			.firstChild(named: "list")?
			.children(named: "user")
			.compactMap { user in
				guard let jid = user.attrs["jid"], let statusNode = user.firstChild(named: "status") else {
					return nil
				}

				let status = statusNode.childText
				return ContactStatus(jid: jid, status: status?.isEmpty == true ? nil : status, setAt: statusNode.timestampDate)
			} ?? []
	}

	public func fetchStatus(_ jids: String..., requestID: String? = nil) async throws -> [ContactStatus] {
		try await fetchStatuses(for: jids, requestID: requestID)
	}

	public func fetchDisappearingDurations(
		for jids: [String],
		requestID: String? = nil
	) async throws -> [ContactDisappearingDuration] {
		let result = try await query(makeUSyncRequest(
			for: jids,
			queryChild: BinaryNode(tag: "disappearing_mode"),
			requestID: requestID
		))
		return result.firstChild(named: "usync")?
			.firstChild(named: "list")?
			.children(named: "user")
			.compactMap { user in
				guard
					let jid = user.attrs["jid"],
					let node = user.firstChild(named: "disappearing_mode"),
					let durationValue = node.attrs["duration"],
					let duration = Int(durationValue)
				else {
					return nil
				}

				return ContactDisappearingDuration(jid: jid, duration: duration, setAt: node.timestampDate)
			} ?? []
	}

	public func fetchDisappearingDuration(
		_ jids: String...,
		requestID: String? = nil
	) async throws -> [ContactDisappearingDuration] {
		try await fetchDisappearingDurations(for: jids, requestID: requestID)
	}

	private func makeUSyncRequest(
		for jids: [String],
		queryChild: BinaryNode,
		requestID: String?
	) throws -> BinaryNode {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		return BinaryNode(
			tag: "iq",
			attrs: ["id": id, "to": "@s.whatsapp.net", "type": "get", "xmlns": "usync"],
			content: .nodes([
				BinaryNode(
					tag: "usync",
					attrs: ["context": "interactive", "mode": "query", "sid": id, "last": "true", "index": "0"],
					content: .nodes([
						BinaryNode(tag: "query", content: .nodes([queryChild])),
						BinaryNode(
							tag: "list",
							content: .nodes(jids.map { jid in
								BinaryNode(tag: "user", attrs: ["jid": JID(jid)?.normalizedUser ?? jid])
							})
						)
					])
				)
			])
		)
	}
}

private extension BinaryNode {
	var childText: String? {
		guard let content else {
			return nil
		}

		switch content {
		case .string(let value):
			return value
		case .data(let data):
			return String(data: data, encoding: .utf8)
		case .nodes:
			return nil
		}
	}

	var timestampDate: Date? {
		guard let timestamp = attrs["t"], let seconds = TimeInterval(timestamp) else {
			return nil
		}

		return Date(timeIntervalSince1970: seconds)
	}
}
