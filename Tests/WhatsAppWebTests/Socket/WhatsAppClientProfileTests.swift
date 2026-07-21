import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client profile and chat")
struct WhatsAppClientProfileTests {
	@Test("queries profile picture URL with normalized target jid")
	func queriesProfilePictureURLWithNormalizedTargetJID() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.profilePictureURL(
				for: "258840000000@c.us",
				type: .image,
				requestID: "picture-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "picture-1")
		#expect(request.attrs["target"] == "258840000000@s.whatsapp.net")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "w:profile:picture")
		#expect(request.firstChild(named: "picture")?.attrs["type"] == "image")
		#expect(request.firstChild(named: "picture")?.attrs["query"] == "url")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "picture-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "picture", attrs: ["url": "https://mmg.whatsapp.net/profile.jpg"])
			])
		))
		#expect(try await task.value == "https://mmg.whatsapp.net/profile.jpg")
	}

	@Test("profile picture URL attaches trusted contact token for user jid")
	func profilePictureURLAttachesTrustedContactTokenForUserJID() async throws {
		let transport = MockProfileWebSocketTransport()
		let keys = InMemorySignalKeyStore(storage: [
			.tcToken: [
				"123@s.whatsapp.net": try TrustedContactTokenCoding.encode(TrustedContactToken(
					token: Data([0xca, 0xfe]),
					timestamp: "9999999999"
				))
			]
		])
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: sampleProfileCredentials(), keys: keys),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let task = Task {
			try await client.profilePictureURL(for: "123@s.whatsapp.net", requestID: "picture-token-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "picture-token-1")
		#expect(request.attrs["target"] == "123@s.whatsapp.net")
		#expect(request.content == .nodes([
			BinaryNode(tag: "picture", attrs: ["type": "preview", "query": "url"]),
			BinaryNode(tag: "tctoken", content: .data(Data([0xca, 0xfe])))
		]))

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "picture-token-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "picture", attrs: ["url": "https://mmg.whatsapp.net/profile-token.jpg"])
			])
		))
		#expect(try await task.value == "https://mmg.whatsapp.net/profile-token.jpg")
	}

	@Test("removes profile picture for another chat with target")
	func removesProfilePictureForAnotherChatWithTarget() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: sampleProfileCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let task = Task {
			try await client.removeProfilePicture(for: "120363000000000000@g.us", requestID: "picture-remove-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "picture-remove-1")
		#expect(request.attrs["target"] == "120363000000000000@g.us")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "w:profile:picture")
		#expect(request.content == nil)

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "picture-remove-1", "type": "result"]))
		try await task.value
	}

	@Test("updates own profile picture without target")
	func updatesOwnProfilePictureWithoutTarget() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: sampleProfileCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let image = Data([0xff, 0xd8, 0xff, 0xd9])
		let task = Task {
			try await client.updateProfilePicture(
				for: "999@s.whatsapp.net",
				imageData: image,
				requestID: "picture-update-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "picture-update-1")
		#expect(request.attrs["target"] == nil)
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "w:profile:picture")
		let picture = try #require(request.firstChild(named: "picture"))
		#expect(picture.attrs["type"] == "image")
		#expect(picture.content == .data(image))

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "picture-update-1", "type": "result"]))
		try await task.value
	}

	@Test("updates profile status with UTF-8 content")
	func updatesProfileStatusWithUTF8Content() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.updateProfileStatus("Disponível no Swift", requestID: "status-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "status-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "status")
		#expect(request.firstChild(named: "status")?.content == .data(Data("Disponível no Swift".utf8)))

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "status-1", "type": "result"]))
		try await task.value
	}

	@Test("fetches blocklist item jids")
	func fetchesBlocklistItemJIDs() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.fetchBlocklist(requestID: "blocklist-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "blocklist-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "blocklist")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "blocklist-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "list", content: .nodes([
					BinaryNode(tag: "item", attrs: ["jid": "111@s.whatsapp.net"]),
					BinaryNode(tag: "item", attrs: ["jid": "222@s.whatsapp.net"])
				]))
			])
		))
		#expect(try await task.value == ["111@s.whatsapp.net", "222@s.whatsapp.net"])
	}

	@Test("blocks PN contacts through stored LID mappings")
	func blocksPNContactsThroughStoredLIDMappings() async throws {
		let transport = MockProfileWebSocketTransport()
		let keys = InMemorySignalKeyStore()
		try await LIDMappingStore.store([
			LIDMapping(pn: "258840000000@s.whatsapp.net", lid: "111222333@lid")
		], in: keys)
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: sampleProfileCredentials(), keys: keys),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let task = Task {
			try await client.updateBlockStatus(for: "258840000000@c.us", action: .block, requestID: "block-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "block-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "blocklist")
		let item = try #require(request.firstChild(named: "item"))
		#expect(item.attrs["action"] == "block")
		#expect(item.attrs["jid"] == "111222333@lid")
		#expect(item.attrs["pn_jid"] == "258840000000@s.whatsapp.net")

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "block-1", "type": "result"]))
		try await task.value
	}

	@Test("unblocks LID contacts without PN attrs")
	func unblocksLIDContactsWithoutPNAttrs() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: sampleProfileCredentials(), keys: InMemorySignalKeyStore()),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let task = Task {
			try await client.updateBlockStatus(for: "111222333@lid", action: .unblock, requestID: "unblock-lid-1")
		}
		let request = try await transport.waitForSentNode()
		let item = try #require(request.firstChild(named: "item"))
		#expect(item.attrs["action"] == "unblock")
		#expect(item.attrs["jid"] == "111222333@lid")
		#expect(item.attrs["pn_jid"] == nil)

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "unblock-lid-1", "type": "result"]))
		try await task.value
	}

	@Test("throws when block PN mapping is missing")
	func throwsWhenBlockPNMappingIsMissing() async throws {
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: sampleProfileCredentials(), keys: InMemorySignalKeyStore())
		)

		await #expect(throws: WhatsAppClientError.missingLIDMappingForPN("258840000000@s.whatsapp.net")) {
			try await client.updateBlockStatus(for: "258840000000@c.us", action: .block, requestID: "block-missing-lid")
		}
	}

	@Test("fetches privacy settings")
	func fetchesPrivacySettings() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.fetchPrivacySettings(requestID: "privacy-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "privacy-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "privacy")
		#expect(request.firstChild(named: "privacy") != nil)

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "privacy-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "privacy", content: .nodes([
					BinaryNode(tag: "category", attrs: ["name": "last", "value": "contacts"]),
					BinaryNode(tag: "category", attrs: ["name": "online", "value": "match_last_seen"])
				]))
			])
		))

		let settings = try await task.value
		#expect(settings == ["last": "contacts", "online": "match_last_seen"])
	}

	@Test("updates online privacy")
	func updatesOnlinePrivacy() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.updateOnlinePrivacy(.matchLastSeen, requestID: "privacy-online-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "privacy-online-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "privacy")
		let category = try #require(request.firstChild(named: "privacy")?.firstChild(named: "category"))
		#expect(category.attrs["name"] == "online")
		#expect(category.attrs["value"] == "match_last_seen")

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "privacy-online-1", "type": "result"]))
		try await task.value
	}

	@Test("updates default disappearing mode")
	func updatesDefaultDisappearingMode() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.updateDefaultDisappearingMode(duration: 86_400, requestID: "default-disappearing-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "default-disappearing-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "disappearing_mode")
		#expect(request.firstChild(named: "disappearing_mode")?.attrs["duration"] == "86400")

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "default-disappearing-1", "type": "result"]))
		try await task.value
	}

	@Test("fetches bot list v2 from all section")
	func fetchesBotListV2FromAllSection() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.botListV2(requestID: "bot-list-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "bot-list-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "bot")
		#expect(request.firstChild(named: "bot")?.attrs["v"] == "2")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "bot-list-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "bot", content: .nodes([
					BinaryNode(tag: "section", attrs: ["type": "featured"], content: .nodes([
						BinaryNode(tag: "bot", attrs: ["jid": "ignore@s.whatsapp.net", "persona_id": "ignore"])
					])),
					BinaryNode(tag: "section", attrs: ["type": "all"], content: .nodes([
						BinaryNode(tag: "bot", attrs: ["jid": "bot-1@s.whatsapp.net", "persona_id": "persona-1"]),
						BinaryNode(tag: "bot", attrs: ["jid": "bot-2@s.whatsapp.net", "persona_id": "persona-2"])
					]))
				]))
			])
		))
		#expect(try await task.value == [
			BotListInfo(jid: "bot-1@s.whatsapp.net", personaId: "persona-1"),
			BotListInfo(jid: "bot-2@s.whatsapp.net", personaId: "persona-2")
		])
	}

	@Test("cleans dirty bits with timestamp")
	func cleansDirtyBitsWithTimestamp() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		try await client.cleanDirtyBits(.accountSync, fromTimestamp: 1_700_000_000, requestID: "dirty-1")
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "dirty-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "urn:xmpp:whatsapp:dirty")
		let clean = try #require(request.firstChild(named: "clean"))
		#expect(clean.attrs["type"] == "account_sync")
		#expect(clean.attrs["timestamp"] == "1700000000")
	}

	@Test("checks WhatsApp users through contact usync")
	func checksWhatsAppUsersThroughContactUSync() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.onWhatsApp(["+258840000000", "258850000000@s.whatsapp.net"], requestID: "on-wa-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "on-wa-1")
		#expect(request.attrs["xmlns"] == "usync")
		let usync = try #require(request.firstChild(named: "usync"))
		#expect(usync.attrs["context"] == "interactive")
		#expect(usync.attrs["mode"] == "query")
		#expect(usync.attrs["sid"] == "on-wa-1")
		#expect(usync.firstChild(named: "query")?.firstChild(named: "contact") != nil)
		let users = try #require(usync.firstChild(named: "list")?.children(named: "user"))
		#expect(users.count == 2)
		#expect(users[0].attrs["jid"] == nil)
		#expect(users[0].childString(named: "contact") == "+258840000000")
		#expect(users[1].childString(named: "contact") == "+258850000000")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "on-wa-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "usync", content: .nodes([
					BinaryNode(tag: "list", content: .nodes([
						BinaryNode(
							tag: "user",
							attrs: ["jid": "258840000000@s.whatsapp.net"],
							content: .nodes([BinaryNode(tag: "contact", attrs: ["type": "in"])])
						),
						BinaryNode(
							tag: "user",
							attrs: ["jid": "258850000000@s.whatsapp.net"],
							content: .nodes([BinaryNode(tag: "contact", attrs: ["type": "out"])])
						)
					]))
				]))
			])
			))
			#expect(try await task.value == [
				OnWhatsAppResult(jid: "258840000000@s.whatsapp.net", exists: true),
				OnWhatsAppResult(jid: "258850000000@s.whatsapp.net", exists: false)
			])
		}

	@Test("fetches contact statuses through usync")
	func fetchesContactStatusesThroughUSync() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.fetchStatuses(for: ["258840000000@c.us"], requestID: "status-usync-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "status-usync-1")
		#expect(request.attrs["xmlns"] == "usync")
		let usync = try #require(request.firstChild(named: "usync"))
		#expect(usync.attrs["context"] == "interactive")
		#expect(usync.attrs["mode"] == "query")
		#expect(usync.attrs["sid"] == "status-usync-1")
		#expect(usync.firstChild(named: "query")?.firstChild(named: "status") != nil)
		#expect(usync.firstChild(named: "list")?.firstChild(named: "user")?.attrs["jid"] == "258840000000@s.whatsapp.net")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "status-usync-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "usync", content: .nodes([
					BinaryNode(tag: "list", content: .nodes([
						BinaryNode(
							tag: "user",
							attrs: ["jid": "258840000000@s.whatsapp.net"],
							content: .nodes([
								BinaryNode(tag: "status", attrs: ["t": "1700000000"], content: .data(Data("Available".utf8)))
							])
						)
					]))
				]))
			])
		))
		let statuses = try await task.value
		#expect(statuses == [
			ContactStatus(jid: "258840000000@s.whatsapp.net", status: "Available", setAt: Date(timeIntervalSince1970: 1_700_000_000))
		])
	}

	@Test("fetches disappearing durations through usync")
	func fetchesDisappearingDurationsThroughUSync() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.fetchDisappearingDurations(for: ["258840000000@c.us"], requestID: "disappearing-1")
		}
		let request = try await transport.waitForSentNode()
		let usync = try #require(request.firstChild(named: "usync"))
		#expect(usync.firstChild(named: "query")?.firstChild(named: "disappearing_mode") != nil)

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "disappearing-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "usync", content: .nodes([
					BinaryNode(tag: "list", content: .nodes([
						BinaryNode(
							tag: "user",
							attrs: ["jid": "258840000000@s.whatsapp.net"],
							content: .nodes([
								BinaryNode(tag: "disappearing_mode", attrs: ["duration": "86400", "t": "1700000100"])
							])
						)
					]))
				]))
			])
		))
		let durations = try await task.value
		#expect(durations == [
			ContactDisappearingDuration(
				jid: "258840000000@s.whatsapp.net",
				duration: 86_400,
				setAt: Date(timeIntervalSince1970: 1_700_000_100)
			)
		])
	}

	@Test("creates audio call links")
	func createsAudioCallLinks() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.createCallLink(type: .audio, requestID: "call-link-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.tag == "call")
		#expect(request.attrs["id"] == "call-link-1")
		#expect(request.attrs["to"] == "@call")
		let linkCreate = try #require(request.firstChild(named: "link_create"))
		#expect(linkCreate.attrs["media"] == "audio")
		#expect(linkCreate.firstChild(named: "event") == nil)

		await transport.enqueueInbound(BinaryNode(
			tag: "call",
			attrs: ["id": "call-link-1"],
			content: .nodes([
				BinaryNode(tag: "link_create", attrs: ["token": "audio-token"])
			])
		))
		#expect(try await task.value == "audio-token")
	}

	@Test("creates scheduled video call links")
	func createsScheduledVideoCallLinks() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.createCallLink(
				type: .video,
				eventStartTime: 1_700_000_000,
				requestID: "call-link-2"
			)
		}
		let request = try await transport.waitForSentNode()
		let linkCreate = try #require(request.firstChild(named: "link_create"))
		#expect(linkCreate.attrs["media"] == "video")
		#expect(linkCreate.firstChild(named: "event")?.attrs["start_time"] == "1700000000")

		await transport.enqueueInbound(BinaryNode(
			tag: "call",
			attrs: ["id": "call-link-2"],
			content: .nodes([
				BinaryNode(tag: "link_create", attrs: ["token": "video-token"])
			])
		))
		#expect(try await task.value == "video-token")
	}
}

private func sampleProfileCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
		signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data([6])),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([8])),
			signature: Data([9]),
			keyID: 1
		),
		registrationID: 559,
		advSecretKey: "adv-secret",
		me: WhatsAppUser(id: "999@s.whatsapp.net", name: "Swift User", lid: "999@lid"),
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true
	)
}
