import Foundation

public struct NewsletterLiveUpdateSubscription: Equatable, Sendable {
	public let duration: String

	public init(duration: String) {
		self.duration = duration
	}
}

public struct NewsletterPicture: Equatable, Sendable {
	public let id: String?
	public let directPath: String?

	public init(id: String? = nil, directPath: String? = nil) {
		self.id = id
		self.directPath = directPath
	}
}

public struct NewsletterMetadata: Equatable, Sendable {
	public let id: String
	public let name: String
	public let creationTime: Int?
	public let description: String?
	public let invite: String?
	public let subscribers: Int?
	public let verification: String?
	public let picture: NewsletterPicture?
	public let muteState: String?

	public init(
		id: String,
		name: String,
		creationTime: Int? = nil,
		description: String? = nil,
		invite: String? = nil,
		subscribers: Int? = nil,
		verification: String? = nil,
		picture: NewsletterPicture? = nil,
		muteState: String? = nil
	) {
		self.id = id
		self.name = name
		self.creationTime = creationTime
		self.description = description
		self.invite = invite
		self.subscribers = subscribers
		self.verification = verification
		self.picture = picture
		self.muteState = muteState
	}
}

public enum NewsletterMetadataLookupType: String, Sendable {
	case invite = "INVITE"
	case jid = "JID"
}

extension WhatsAppClient {
	public func newsletterCreate(
		name: String,
		description: String? = nil,
		requestID: String? = nil
	) async throws -> NewsletterMetadata {
		let response = try await executeWMexQuery(
			variables: ["input": ["name": name, "description": description as Any]],
			queryID: "8823471724422422",
			dataPath: "xwa2_newsletter_create",
			requestID: requestID
		)
		return try parseNewsletterCreateResponse(response.object, dataPath: "xwa2_newsletter_create")
	}

	public func newsletterMetadata(
		type: NewsletterMetadataLookupType,
		key: String,
		requestID: String? = nil
	) async throws -> NewsletterMetadata? {
		let response = try await executeWMexQuery(
			variables: [
				"fetch_creation_time": true,
				"fetch_full_image": true,
				"fetch_viewer_metadata": true,
				"input": [
					"key": key,
					"type": type.rawValue
				]
			],
			queryID: "6563316087068696",
			dataPath: "xwa2_newsletter",
			requestID: requestID
		)
		return try parseNewsletterMetadata(response.object, dataPath: "xwa2_newsletter")
	}

	public func newsletterSubscribers(_ jid: String, requestID: String? = nil) async throws -> Int {
		let response = try await executeWMexQuery(
			variables: ["newsletter_id": jid],
			queryID: "9783111038412085",
			dataPath: "xwa2_newsletter_subscribers",
			requestID: requestID
		)
		guard let subscribers = response["subscribers"] as? Int else {
			throw WMexQueryError.invalidResponse(path: "xwa2_newsletter_subscribers")
		}

		return subscribers
	}

	public func newsletterAdminCount(_ jid: String, requestID: String? = nil) async throws -> Int {
		let response = try await executeWMexQuery(
			variables: ["newsletter_id": jid],
			queryID: "7130823597031706",
			dataPath: "xwa2_newsletter_admin",
			requestID: requestID
		)
		guard let count = response["admin_count"] as? Int else {
			throw WMexQueryError.invalidResponse(path: "xwa2_newsletter_admin")
		}

		return count
	}

	public func newsletterUpdateName(_ jid: String, name: String, requestID: String? = nil) async throws {
		try await newsletterUpdate(jid, updates: ["name": name], requestID: requestID)
	}

	public func newsletterUpdateDescription(_ jid: String, description: String, requestID: String? = nil) async throws {
		try await newsletterUpdate(jid, updates: ["description": description], requestID: requestID)
	}

	public func newsletterRemovePicture(_ jid: String, requestID: String? = nil) async throws {
		try await newsletterUpdate(jid, updates: ["picture": ""], requestID: requestID)
	}

	public func newsletterUpdatePicture(
		_ jid: String,
		imageData: Data,
		dimensions: ProfilePictureDimensions = ProfilePictureDimensions(),
		requestID: String? = nil
	) async throws {
		let pictureData = try ProfilePictureImageProcessor.makeJPEGData(from: imageData, dimensions: dimensions)
		try await newsletterUpdate(jid, updates: ["picture": pictureData.base64EncodedString()], requestID: requestID)
	}

	public func newsletterFollow(_ jid: String, requestID: String? = nil) async throws {
		_ = try await executeWMexQuery(
			variables: ["newsletter_id": jid],
			queryID: "24404358912487870",
			dataPath: "xwa2_newsletter_join_v2",
			requestID: requestID
		)
	}

	public func newsletterChangeOwner(_ jid: String, newOwnerJID: String, requestID: String? = nil) async throws {
		_ = try await executeWMexQuery(
			variables: ["newsletter_id": jid, "user_id": newOwnerJID],
			queryID: "7341777602580933",
			dataPath: "xwa2_newsletter_change_owner",
			requestID: requestID
		)
	}

	public func newsletterDemote(_ jid: String, userJID: String, requestID: String? = nil) async throws {
		_ = try await executeWMexQuery(
			variables: ["newsletter_id": jid, "user_id": userJID],
			queryID: "6551828931592903",
			dataPath: "xwa2_newsletter_demote",
			requestID: requestID
		)
	}

	public func newsletterUnfollow(_ jid: String, requestID: String? = nil) async throws {
		_ = try await executeWMexQuery(
			variables: ["newsletter_id": jid],
			queryID: "9767147403369991",
			dataPath: "xwa2_newsletter_leave_v2",
			requestID: requestID
		)
	}

	public func newsletterMute(_ jid: String, requestID: String? = nil) async throws {
		_ = try await executeWMexQuery(
			variables: ["newsletter_id": jid],
			queryID: "29766401636284406",
			dataPath: "xwa2_newsletter_mute_v2",
			requestID: requestID
		)
	}

	public func newsletterUnmute(_ jid: String, requestID: String? = nil) async throws {
		_ = try await executeWMexQuery(
			variables: ["newsletter_id": jid],
			queryID: "9864994326891137",
			dataPath: "xwa2_newsletter_unmute_v2",
			requestID: requestID
		)
	}

	public func newsletterDelete(_ jid: String, requestID: String? = nil) async throws {
		_ = try await executeWMexQuery(
			variables: ["newsletter_id": jid],
			queryID: "30062808666639665",
			dataPath: "xwa2_newsletter_delete_v2",
			requestID: requestID
		)
	}

	public func newsletterReactMessage(
		_ jid: String,
		serverID: String,
		reaction: String?,
		requestID: String? = nil
	) async throws {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		var attrs = [
			("id", id),
			("to", jid),
			("type", "reaction"),
			("server_id", serverID)
		]
		if reaction == nil {
			attrs.append(("edit", "7"))
		}

		_ = try await query(
			BinaryNode(
				tag: "message",
				attrs: BinaryNodeAttributes(attrs),
				content: .nodes([
					BinaryNode(tag: "reaction", attrs: reaction.map { ["code": $0] } ?? [:])
				])
			)
		)
	}

	public func newsletterFetchMessages(
		_ jid: String,
		count: Int,
		since: Int? = nil,
		after: Int? = nil,
		requestID: String? = nil
	) async throws -> BinaryNode {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		var updateAttrs = [("count", String(count))]
		if let since {
			updateAttrs.append(("since", String(since)))
		}

		if let after {
			updateAttrs.append(("after", String(after)))
		}

		return try await query(
			BinaryNode(
				tag: "iq",
				attrs: [
					"id": id,
					"type": "get",
					"xmlns": "newsletter",
					"to": jid
				],
				content: .nodes([
					BinaryNode(tag: "message_updates", attrs: BinaryNodeAttributes(updateAttrs))
				])
			)
		)
	}

	public func subscribeNewsletterUpdates(
		_ jid: String,
		requestID: String? = nil
	) async throws -> NewsletterLiveUpdateSubscription? {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let result = try await query(
			BinaryNode(
				tag: "iq",
				attrs: [
					"id": id,
					"type": "set",
					"xmlns": "newsletter",
					"to": jid
				],
				content: .nodes([BinaryNode(tag: "live_updates")])
			)
		)
		return result.firstChild(named: "live_updates")?.attrs["duration"].map {
			NewsletterLiveUpdateSubscription(duration: $0)
		}
	}

	private func newsletterUpdate(_ jid: String, updates: [String: Any], requestID: String?) async throws {
		var updatePayload = updates
		updatePayload["settings"] = NSNull()
		_ = try await executeWMexQuery(
			variables: [
				"newsletter_id": jid,
				"updates": updatePayload
			],
			queryID: "24250201037901610",
			dataPath: "xwa2_newsletter_update",
			requestID: requestID
		)
	}

	private func parseNewsletterCreateResponse(_ response: [String: Any], dataPath: String) throws -> NewsletterMetadata {
		guard
			let id = response["id"] as? String,
			let thread = response["thread_metadata"] as? [String: Any],
			let name = (thread["name"] as? [String: Any])?["text"] as? String
		else {
			throw WMexQueryError.invalidResponse(path: dataPath)
		}

		let picture = thread["picture"] as? [String: Any]
		let viewer = response["viewer_metadata"] as? [String: Any]
		return NewsletterMetadata(
			id: id,
			name: name,
			creationTime: (thread["creation_time"] as? String).flatMap(Int.init),
			description: (thread["description"] as? [String: Any])?["text"] as? String,
			invite: thread["invite"] as? String,
			subscribers: (thread["subscribers_count"] as? String).flatMap(Int.init),
			verification: thread["verification"] as? String,
			picture: NewsletterPicture(
				id: picture?["id"] as? String,
				directPath: picture?["direct_path"] as? String
			),
			muteState: viewer?["mute"] as? String
		)
	}

	private func parseNewsletterMetadata(_ response: [String: Any], dataPath: String) throws -> NewsletterMetadata? {
		let metadata = (response["result"] as? [String: Any]) ?? response
		guard let id = metadata["id"] as? String else {
			return nil
		}

		let picture = metadata["picture"] as? [String: Any]
		return NewsletterMetadata(
			id: id,
			name: metadata["name"] as? String ?? "",
			creationTime: metadata["creation_time"] as? Int,
			description: metadata["description"] as? String,
			invite: metadata["invite"] as? String,
			subscribers: metadata["subscribers"] as? Int,
			verification: metadata["verification"] as? String,
			picture: NewsletterPicture(
				id: picture?["id"] as? String,
				directPath: picture?["directPath"] as? String ?? picture?["direct_path"] as? String
			),
			muteState: metadata["mute_state"] as? String
		)
	}
}

private extension BinaryNode {
	var contentData: Data? {
		switch content {
		case let .data(data):
			data
		case let .string(string):
			Data(string.utf8)
		case .nodes, .none:
			nil
		}
	}
}
