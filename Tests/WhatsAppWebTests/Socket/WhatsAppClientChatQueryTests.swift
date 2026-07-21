import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client chat queries")
struct WhatsAppClientChatQueryTests {
	@Test("checks WhatsApp users through contact usync")
	func checksWhatsAppUsersThroughContactUSync() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: sampleChatQueryCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let task = Task {
			try await client.onWhatsApp([
				"+123456789",
				"987654321@s.whatsapp.net",
				"555@lid"
			], requestID: "contact-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "contact-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "usync")
		let usync = try #require(request.firstChild(named: "usync"))
		#expect(usync.attrs["context"] == "interactive")
		#expect(usync.attrs["mode"] == "query")
		#expect(usync.attrs["sid"] == "contact-1")
		#expect(usync.firstChild(named: "query")?.firstChild(named: "contact") != nil)
		let users = try #require(usync.firstChild(named: "list")?.children(named: "user"))
		#expect(users.map { $0.firstChild(named: "contact")?.childText } == ["+123456789", "+987654321"])

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "contact-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "usync", content: .nodes([
					BinaryNode(tag: "list", content: .nodes([
						BinaryNode(tag: "user", attrs: ["jid": "123456789@s.whatsapp.net"], content: .nodes([
							BinaryNode(tag: "contact", attrs: ["type": "in"])
						])),
						BinaryNode(tag: "user", attrs: ["jid": "987654321@s.whatsapp.net"], content: .nodes([
							BinaryNode(tag: "contact", attrs: ["type": "out"])
						]))
					]))
				]))
			])
		))

		#expect(try await task.value == [
			OnWhatsAppResult(jid: "123456789@s.whatsapp.net", exists: true),
			OnWhatsAppResult(jid: "987654321@s.whatsapp.net", exists: false)
		])
	}

	@Test("maps phone-number users to LIDs through background usync")
	func mapsPhoneNumberUsersToLIDsThroughBackgroundUSync() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: sampleChatQueryCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let task = Task {
			try await client.pnFromLIDUSync([
				"123456789@s.whatsapp.net",
				"987654321@s.whatsapp.net",
				"555@lid",
				"777@hosted.lid"
			], requestID: "lid-map-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "lid-map-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "usync")
		let usync = try #require(request.firstChild(named: "usync"))
		#expect(usync.attrs["context"] == "background")
		#expect(usync.attrs["mode"] == "query")
		#expect(usync.attrs["sid"] == "lid-map-1")
		#expect(usync.firstChild(named: "query")?.firstChild(named: "lid") != nil)
		let users = try #require(usync.firstChild(named: "list")?.children(named: "user"))
		#expect(users.map { $0.attrs["jid"] } == ["123456789@s.whatsapp.net", "987654321@s.whatsapp.net"])
		#expect(users.allSatisfy { $0.content == nil })

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "lid-map-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "usync", content: .nodes([
					BinaryNode(tag: "list", content: .nodes([
						BinaryNode(tag: "user", attrs: ["jid": "123456789@s.whatsapp.net"], content: .nodes([
							BinaryNode(tag: "lid", attrs: ["val": "111@lid"])
						])),
						BinaryNode(tag: "user", attrs: ["jid": "987654321@s.whatsapp.net"]),
						BinaryNode(tag: "user", attrs: ["jid": "222222222@s.whatsapp.net"], content: .nodes([
							BinaryNode(tag: "lid", attrs: ["val": "222@lid"])
						]))
					]))
				]))
			])
		))

		#expect(try await task.value == [
			LIDMapping(pn: "123456789@s.whatsapp.net", lid: "111@lid"),
			LIDMapping(pn: "222222222@s.whatsapp.net", lid: "222@lid")
		])
	}

	@Test("fetches AB props with saved hash and updates credentials hash")
	func fetchesABPropsWithSavedHashAndUpdatesCredentialsHash() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: sampleChatQueryCredentials(lastPropertyHash: "old-hash"),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let task = Task {
			try await client.fetchProps(requestID: "props-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "props-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "abt")
		let propsRequest = try #require(request.firstChild(named: "props"))
		#expect(propsRequest.attrs["protocol"] == "1")
		#expect(propsRequest.attrs["hash"] == "old-hash")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "props-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "props", attrs: ["hash": "new-hash"], content: .nodes([
					BinaryNode(tag: "prop", attrs: ["name": "10518", "value": "true"]),
					BinaryNode(tag: "prop", attrs: ["config_code": "9666", "config_value": "1"])
				]))
			])
		))

		#expect(try await task.value == ["10518": "true", "9666": "1"])
		let updatedHash = await client.authenticationState?.credentials.lastPropertyHash
		#expect(updatedHash == "new-hash")
	}

	@Test("fetching AB props tolerates duplicate prop keys")
	func fetchingABPropsToleratesDuplicatePropKeys() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: sampleChatQueryCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let task = Task {
			try await client.fetchProps(requestID: "props-duplicates")
		}
		_ = try await transport.waitForSentNode()

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "props-duplicates", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "props", content: .nodes([
					BinaryNode(tag: "prop", attrs: ["name": "10518", "value": "true"]),
					BinaryNode(tag: "prop", attrs: ["name": "10518", "value": "false"])
				]))
			])
		))

		#expect(try await task.value == ["10518": "false"])
	}

	@Test("Baileys bot list alias fetches bot list v2")
	func baileysBotListAliasFetchesBotListV2() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: sampleChatQueryCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let task = Task {
			try await client.getBotListV2(requestID: "bot-list-alias")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "bot-list-alias")
		#expect(request.attrs["xmlns"] == "bot")
		#expect(request.firstChild(named: "bot")?.attrs["v"] == "2")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "bot-list-alias", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "bot", content: .nodes([
					BinaryNode(tag: "section", attrs: ["type": "all"], content: .nodes([
						BinaryNode(tag: "bot", attrs: ["jid": "bot@s.whatsapp.net", "persona_id": "persona"])
					]))
				]))
			])
		))

		#expect(try await task.value == [
			BotListInfo(jid: "bot@s.whatsapp.net", personaId: "persona")
		])
	}
}

private func sampleChatQueryCredentials(lastPropertyHash: String? = nil) -> AuthenticationCredentials {
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
		registered: true,
		lastPropertyHash: lastPropertyHash
	)
}
