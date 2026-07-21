import AppKit
import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client newsletters")
struct WhatsAppClientNewsletterTests {
	@Test("creates a newsletter through WMex and parses metadata")
	func createsNewsletterThroughWMexAndParsesMetadata() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.newsletterCreate(
				name: "Swift News",
				description: "Updates from Swift",
				requestID: "newsletter-create-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "newsletter-create-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "w:mex")
		let query = try #require(request.firstChild(named: "query"))
		#expect(query.attrs["query_id"] == "8823471724422422")
		let variables = try wmexVariables(from: query)
		#expect(variables["input.name"] == "Swift News")
		#expect(variables["input.description"] == "Updates from Swift")

		await transport.enqueueInbound(wmexResponse(
			id: "newsletter-create-1",
			dataPath: "xwa2_newsletter_create",
			object: [
				"id": "120363000000000010@newsletter",
				"thread_metadata": [
					"creation_time": "1700000000",
					"description": ["text": "Updates from Swift"],
					"invite": "invite-code",
					"name": ["text": "Swift News"],
					"picture": ["direct_path": "/direct/path", "id": "picture-id"],
					"subscribers_count": "42",
					"verification": "UNVERIFIED"
				],
				"viewer_metadata": ["mute": "OFF"]
			]
		))
		let metadata = try await task.value
		#expect(metadata == NewsletterMetadata(
			id: "120363000000000010@newsletter",
			name: "Swift News",
			creationTime: 1_700_000_000,
			description: "Updates from Swift",
			invite: "invite-code",
			subscribers: 42,
			verification: "UNVERIFIED",
			picture: NewsletterPicture(id: "picture-id", directPath: "/direct/path"),
			muteState: "OFF"
		))
	}

	@Test("fetches newsletter subscriber count through WMex")
	func fetchesNewsletterSubscriberCountThroughWMex() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.newsletterSubscribers(
				"120363000000000010@newsletter",
				requestID: "newsletter-subscribers-1"
			)
		}
		let request = try await transport.waitForSentNode()
		let query = try #require(request.firstChild(named: "query"))
		#expect(query.attrs["query_id"] == "9783111038412085")
		#expect(try wmexVariables(from: query)["newsletter_id"] == "120363000000000010@newsletter")

		await transport.enqueueInbound(wmexResponse(
			id: "newsletter-subscribers-1",
			dataPath: "xwa2_newsletter_subscribers",
			object: ["subscribers": 42]
		))
		#expect(try await task.value == 42)
	}

	@Test("creates newsletter with null description when omitted")
	func createsNewsletterWithNullDescriptionWhenOmitted() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.newsletterCreate(
				name: "Swift News",
				requestID: "newsletter-create-no-description-1"
			)
		}
		let request = try await transport.waitForSentNode()
		let query = try #require(request.firstChild(named: "query"))
		let variables = try wmexVariables(from: query)
		#expect(variables["input.name"] == "Swift News")
		#expect(variables["input.description"] == "null")

		await transport.enqueueInbound(wmexResponse(
			id: "newsletter-create-no-description-1",
			dataPath: "xwa2_newsletter_create",
			object: [
				"id": "120363000000000010@newsletter",
				"thread_metadata": [
					"creation_time": "1700000000",
					"description": ["text": ""],
					"invite": "invite-code",
					"name": ["text": "Swift News"],
					"picture": [:],
					"subscribers_count": "0",
					"verification": "UNVERIFIED"
				],
				"viewer_metadata": ["mute": "OFF"]
			]
		))
		#expect(try await task.value.name == "Swift News")
	}

	@Test("follows a newsletter through WMex")
	func followsNewsletterThroughWMex() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.newsletterFollow(
				"120363000000000010@newsletter",
				requestID: "newsletter-follow-1"
			)
		}
		let request = try await transport.waitForSentNode()
		let query = try #require(request.firstChild(named: "query"))
		#expect(query.attrs["query_id"] == "24404358912487870")
		#expect(try wmexVariables(from: query)["newsletter_id"] == "120363000000000010@newsletter")

		await transport.enqueueInbound(wmexResponse(
			id: "newsletter-follow-1",
			dataPath: "xwa2_newsletter_join_v2",
			object: ["ok": true]
		))
		try await task.value
	}

	@Test("fetches newsletter metadata through WMex")
	func fetchesNewsletterMetadataThroughWMex() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.newsletterMetadata(
				type: .jid,
				key: "120363000000000010@newsletter",
				requestID: "newsletter-metadata-1"
			)
		}
		let request = try await transport.waitForSentNode()
		let query = try #require(request.firstChild(named: "query"))
		#expect(query.attrs["query_id"] == "6563316087068696")
		let variables = try wmexVariables(from: query)
		#expect(variables["fetch_creation_time"] == "true")
		#expect(variables["fetch_full_image"] == "true")
		#expect(variables["fetch_viewer_metadata"] == "true")
		#expect(variables["input.key"] == "120363000000000010@newsletter")
		#expect(variables["input.type"] == "JID")

		await transport.enqueueInbound(wmexResponse(
			id: "newsletter-metadata-1",
			dataPath: "xwa2_newsletter",
			object: [
				"result": [
					"id": "120363000000000010@newsletter",
					"name": "Swift News",
					"description": "Updates from Swift",
					"creation_time": 1_700_000_000,
					"subscribers": 42,
					"verification": "UNVERIFIED",
					"mute_state": "OFF",
					"picture": ["directPath": "/direct/path", "id": "picture-id"]
				]
			]
		))
		#expect(try await task.value == NewsletterMetadata(
			id: "120363000000000010@newsletter",
			name: "Swift News",
			creationTime: 1_700_000_000,
			description: "Updates from Swift",
			subscribers: 42,
			verification: "UNVERIFIED",
			picture: NewsletterPicture(id: "picture-id", directPath: "/direct/path"),
			muteState: "OFF"
		))
	}

	@Test("runs newsletter mute unmute unfollow and delete through WMex")
	func runsNewsletterMuteUnmuteUnfollowAndDeleteThroughWMex() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let calls: [(String, String, String, @Sendable () async throws -> Void)] = [
			("newsletter-mute-1", "29766401636284406", "xwa2_newsletter_mute_v2", {
				try await client.newsletterMute("120363000000000010@newsletter", requestID: "newsletter-mute-1")
			}),
			("newsletter-unmute-1", "9864994326891137", "xwa2_newsletter_unmute_v2", {
				try await client.newsletterUnmute("120363000000000010@newsletter", requestID: "newsletter-unmute-1")
			}),
			("newsletter-unfollow-1", "9767147403369991", "xwa2_newsletter_leave_v2", {
				try await client.newsletterUnfollow("120363000000000010@newsletter", requestID: "newsletter-unfollow-1")
			}),
			("newsletter-delete-1", "30062808666639665", "xwa2_newsletter_delete_v2", {
				try await client.newsletterDelete("120363000000000010@newsletter", requestID: "newsletter-delete-1")
			})
		]

		for (index, call) in calls.enumerated() {
			let task = Task { try await call.3() }
			let request = try await transport.waitForSentNode(at: index)
			let query = try #require(request.firstChild(named: "query"))
			#expect(request.attrs["id"] == call.0)
			#expect(query.attrs["query_id"] == call.1)
			#expect(try wmexVariables(from: query)["newsletter_id"] == "120363000000000010@newsletter")

			await transport.enqueueInbound(wmexResponse(id: call.0, dataPath: call.2, object: ["ok": true]))
			try await task.value
		}
	}

	@Test("fetches newsletter admin count through WMex")
	func fetchesNewsletterAdminCountThroughWMex() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.newsletterAdminCount(
				"120363000000000010@newsletter",
				requestID: "newsletter-admin-count-1"
			)
		}
		let request = try await transport.waitForSentNode()
		let query = try #require(request.firstChild(named: "query"))
		#expect(query.attrs["query_id"] == "7130823597031706")
		#expect(try wmexVariables(from: query)["newsletter_id"] == "120363000000000010@newsletter")

		await transport.enqueueInbound(wmexResponse(
			id: "newsletter-admin-count-1",
			dataPath: "xwa2_newsletter_admin",
			object: ["admin_count": 3]
		))
		#expect(try await task.value == 3)
	}

	@Test("updates newsletter name description and removes picture through WMex")
	func updatesNewsletterNameDescriptionAndRemovesPictureThroughWMex() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let calls: [(String, String, String, @Sendable () async throws -> Void)] = [
			("newsletter-name-1", "updates.name", "Swift News", {
				try await client.newsletterUpdateName(
					"120363000000000010@newsletter",
					name: "Swift News",
					requestID: "newsletter-name-1"
				)
			}),
			("newsletter-description-1", "updates.description", "Daily Swift updates", {
				try await client.newsletterUpdateDescription(
					"120363000000000010@newsletter",
					description: "Daily Swift updates",
					requestID: "newsletter-description-1"
				)
			}),
			("newsletter-remove-picture-1", "updates.picture", "", {
				try await client.newsletterRemovePicture(
					"120363000000000010@newsletter",
					requestID: "newsletter-remove-picture-1"
				)
			})
		]

		for (index, call) in calls.enumerated() {
			let task = Task { try await call.3() }
			let request = try await transport.waitForSentNode(at: index)
			let query = try #require(request.firstChild(named: "query"))
			let variables = try wmexVariables(from: query)
			#expect(request.attrs["id"] == call.0)
			#expect(query.attrs["query_id"] == "24250201037901610")
			#expect(variables["newsletter_id"] == "120363000000000010@newsletter")
			#expect(variables["updates.settings"] == "null")
			#expect(variables[call.1] == call.2)

			await transport.enqueueInbound(wmexResponse(
				id: call.0,
				dataPath: "xwa2_newsletter_update",
				object: ["ok": true]
			))
			try await task.value
		}
	}

	@Test("updates newsletter picture through WMex with processed JPEG")
	func updatesNewsletterPictureThroughWMexWithProcessedJPEG() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()
		let imageData = try makeTestPNG(width: 20, height: 10)

		let task = Task {
			try await client.newsletterUpdatePicture(
				"120363000000000010@newsletter",
				imageData: imageData,
				requestID: "newsletter-picture-1"
			)
		}
		let request = try await transport.waitForSentNode()
		let query = try #require(request.firstChild(named: "query"))
		let variables = try wmexVariables(from: query)
		let pictureBase64 = try #require(variables["updates.picture"])
		let pictureData = try #require(Data(base64Encoded: pictureBase64))
		let bitmap = try #require(NSBitmapImageRep(data: pictureData))
		#expect(query.attrs["query_id"] == "24250201037901610")
		#expect(variables["newsletter_id"] == "120363000000000010@newsletter")
		#expect(variables["updates.settings"] == "null")
		#expect(bitmap.pixelsWide == 640)
		#expect(bitmap.pixelsHigh == 640)

		await transport.enqueueInbound(wmexResponse(
			id: "newsletter-picture-1",
			dataPath: "xwa2_newsletter_update",
			object: ["ok": true]
		))
		try await task.value
	}

	@Test("changes owner and demotes newsletter admins through WMex")
	func changesOwnerAndDemotesNewsletterAdminsThroughWMex() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let calls: [(String, String, String, @Sendable () async throws -> Void)] = [
			("newsletter-change-owner-1", "7341777602580933", "xwa2_newsletter_change_owner", {
				try await client.newsletterChangeOwner(
					"120363000000000010@newsletter",
					newOwnerJID: "12345@s.whatsapp.net",
					requestID: "newsletter-change-owner-1"
				)
			}),
			("newsletter-demote-1", "6551828931592903", "xwa2_newsletter_demote", {
				try await client.newsletterDemote(
					"120363000000000010@newsletter",
					userJID: "12345@s.whatsapp.net",
					requestID: "newsletter-demote-1"
				)
			})
		]

		for (index, call) in calls.enumerated() {
			let task = Task { try await call.3() }
			let request = try await transport.waitForSentNode(at: index)
			let query = try #require(request.firstChild(named: "query"))
			let variables = try wmexVariables(from: query)
			#expect(request.attrs["id"] == call.0)
			#expect(query.attrs["query_id"] == call.1)
			#expect(variables["newsletter_id"] == "120363000000000010@newsletter")
			#expect(variables["user_id"] == "12345@s.whatsapp.net")

			await transport.enqueueInbound(wmexResponse(id: call.0, dataPath: call.2, object: ["ok": true]))
			try await task.value
		}
	}

	@Test("reacts to a newsletter message")
	func reactsToNewsletterMessage() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.newsletterReactMessage(
				"120363000000000010@newsletter",
				serverID: "server-message-1",
				reaction: "OK",
				requestID: "newsletter-reaction-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.tag == "message")
		#expect(request.attrs["id"] == "newsletter-reaction-1")
		#expect(request.attrs["to"] == "120363000000000010@newsletter")
		#expect(request.attrs["type"] == "reaction")
		#expect(request.attrs["server_id"] == "server-message-1")
		#expect(request.attrs["edit"] == nil)
		#expect(request.firstChild(named: "reaction")?.attrs["code"] == "OK")

		await transport.enqueueInbound(BinaryNode(
			tag: "message",
			attrs: ["id": "newsletter-reaction-1", "type": "result"]
		))
		try await task.value
	}

	@Test("removes a newsletter message reaction")
	func removesNewsletterMessageReaction() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.newsletterReactMessage(
				"120363000000000010@newsletter",
				serverID: "server-message-1",
				reaction: nil,
				requestID: "newsletter-reaction-remove-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["edit"] == "7")
		#expect(request.firstChild(named: "reaction")?.attrs.orderedEntries.count == 0)

		await transport.enqueueInbound(BinaryNode(
			tag: "message",
			attrs: ["id": "newsletter-reaction-remove-1", "type": "result"]
		))
		try await task.value
	}

	@Test("fetches newsletter message updates with cursors")
	func fetchesNewsletterMessageUpdatesWithCursors() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.newsletterFetchMessages(
				"120363000000000010@newsletter",
				count: 20,
				since: 1_700_000_000,
				after: 123,
				requestID: "newsletter-messages-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "newsletter-messages-1")
		#expect(request.attrs["to"] == "120363000000000010@newsletter")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "newsletter")
		let updates = try #require(request.firstChild(named: "message_updates"))
		#expect(updates.attrs["count"] == "20")
		#expect(updates.attrs["since"] == "1700000000")
		#expect(updates.attrs["after"] == "123")

		let response = BinaryNode(
			tag: "iq",
			attrs: ["id": "newsletter-messages-1", "type": "result"],
			content: .nodes([BinaryNode(tag: "message_updates")])
		)
		await transport.enqueueInbound(response)
		#expect(try await task.value == response)
	}

	@Test("subscribes to newsletter live updates and returns duration")
	func subscribesToNewsletterLiveUpdatesAndReturnsDuration() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.subscribeNewsletterUpdates(
				"120363000000000010@newsletter",
				requestID: "newsletter-live-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "newsletter-live-1")
		#expect(request.attrs["to"] == "120363000000000010@newsletter")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "newsletter")
		#expect(request.firstChild(named: "live_updates") != nil)

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "newsletter-live-1", "type": "result"],
			content: .nodes([BinaryNode(tag: "live_updates", attrs: ["duration": "86400"])])
		))
		#expect(try await task.value == NewsletterLiveUpdateSubscription(duration: "86400"))
	}
}

private func wmexVariables(from query: BinaryNode) throws -> [String: String] {
	let data = try #require(query.contentData)
	let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
	let variables = try #require(json?["variables"] as? [String: Any])
	var flattened: [String: String] = [:]
	for (key, value) in variables {
		if let string = value as? String {
			flattened[key] = string
		} else if let bool = value as? Bool {
			flattened[key] = String(bool)
		} else if let nested = value as? [String: Any] {
			for (nestedKey, nestedValue) in nested {
				if let string = nestedValue as? String {
					flattened["\(key).\(nestedKey)"] = string
				} else if let bool = nestedValue as? Bool {
					flattened["\(key).\(nestedKey)"] = String(bool)
				} else if nestedValue is NSNull {
					flattened["\(key).\(nestedKey)"] = "null"
				}
			}
		} else if value is NSNull {
			flattened[key] = "null"
		}
	}
	return flattened
}

private func wmexResponse(id: String, dataPath: String, object: [String: Any]) -> BinaryNode {
	let data = try! JSONSerialization.data(withJSONObject: ["data": [dataPath: object]], options: [.sortedKeys])
	return BinaryNode(
		tag: "iq",
		attrs: ["id": id, "type": "result"],
		content: .nodes([BinaryNode(tag: "result", content: .data(data))])
	)
}

private func makeTestPNG(width: Int, height: Int) throws -> Data {
	let image = NSImage(size: NSSize(width: width, height: height))
	image.lockFocus()
	NSColor.systemBlue.setFill()
	NSRect(x: 0, y: 0, width: width, height: height).fill()
	image.unlockFocus()
	let data = try #require(image.tiffRepresentation)
	let bitmap = try #require(NSBitmapImageRep(data: data))
	return try #require(bitmap.representation(using: .png, properties: [:]))
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
