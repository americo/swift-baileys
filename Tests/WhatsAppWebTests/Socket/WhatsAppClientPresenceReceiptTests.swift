import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client presence and receipts")
struct WhatsAppClientPresenceReceiptTests {
	@Test("sends available presence with the authenticated display name")
	func sendsAvailablePresenceWithAuthenticatedDisplayName() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePresenceCredentials(name: "Swift@Bot"),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		try await client.sendPresenceUpdate(.available)

		let stanza = try await firstSentNode(from: transport)
		#expect(stanza == BinaryNode(
			tag: "presence",
			attrs: ["name": "SwiftBot", "type": "available"]
		))
	}

	@Test("ignores available presence when authenticated user has no display name")
	func ignoresAvailablePresenceWhenAuthenticatedUserHasNoDisplayName() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePresenceCredentials(name: nil),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		try await client.sendPresenceUpdate(.available)

		#expect(await transport.sentFrames.isEmpty)
	}

	@Test("sends recording chat state to a chat")
	func sendsRecordingChatStateToChat() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePresenceCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		try await client.sendPresenceUpdate(.recording, to: "123@s.whatsapp.net")

		let stanza = try await firstSentNode(from: transport)
		#expect(stanza == BinaryNode(
			tag: "chatstate",
			attrs: ["from": "999@s.whatsapp.net", "to": "123@s.whatsapp.net"],
			content: .nodes([
				BinaryNode(tag: "composing", attrs: ["media": "audio"])
			])
		))
	}

	@Test("presenceSubscribe attaches trusted contact token for user jid")
	func presenceSubscribeAttachesTrustedContactTokenForUserJID() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let keys = InMemorySignalKeyStore(storage: [
			.tcToken: [
				"123@s.whatsapp.net": try TrustedContactTokenCoding.encode(TrustedContactToken(
					token: Data([0xaa, 0xbb]),
					timestamp: "9999999999"
				))
			]
		])
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePresenceCredentials(),
				keys: keys
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		try await client.presenceSubscribe(to: "123@s.whatsapp.net", id: "presence-1")

		let stanza = try await firstSentNode(from: transport)
		#expect(stanza == BinaryNode(
			tag: "presence",
			attrs: ["to": "123@s.whatsapp.net", "id": "presence-1", "type": "subscribe"],
			content: .nodes([
				BinaryNode(tag: "tctoken", content: .data(Data([0xaa, 0xbb])))
			])
		))
	}

	@Test("sends read receipts with extra message ids in the receipt list")
	func sendsReadReceiptsWithExtraMessageIDs() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		try await client.sendReceipt(
			to: "123@s.whatsapp.net",
			participant: "456@s.whatsapp.net",
			messageIDs: ["msg-1", "msg-2", "msg-3"],
			type: .read,
			timestampSeconds: 1_700_000_000
		)

		let stanza = try await firstSentNode(from: transport)
		#expect(stanza == BinaryNode(
			tag: "receipt",
			attrs: [
				"id": "msg-1",
				"to": "123@s.whatsapp.net",
				"participant": "456@s.whatsapp.net",
				"type": "read",
				"t": "1700000000"
			],
			content: .nodes([
				BinaryNode(tag: "list", content: .nodes([
					BinaryNode(tag: "item", attrs: ["id": "msg-2"]),
					BinaryNode(tag: "item", attrs: ["id": "msg-3"])
				]))
			])
		))
	}

	@Test("readMessages groups incoming keys by chat and participant")
	func readMessagesGroupsIncomingKeysByChatAndParticipant() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		try await client.readMessages([
			WhatsAppMessageKey(remoteJID: "123@g.us", fromMe: false, id: "msg-1", participant: "111@s.whatsapp.net"),
			WhatsAppMessageKey(remoteJID: "123@g.us", fromMe: false, id: "msg-2", participant: "111@s.whatsapp.net"),
			WhatsAppMessageKey(remoteJID: "123@g.us", fromMe: false, id: "msg-3", participant: "222@s.whatsapp.net"),
			WhatsAppMessageKey(remoteJID: "999@s.whatsapp.net", fromMe: true, id: "own-message")
		], type: .readSelf, timestampSeconds: 1_700_000_000)

		let stanzas = try await sentNodes(from: transport)
		#expect(stanzas == [
			BinaryNode(
				tag: "receipt",
				attrs: [
					"id": "msg-1",
					"to": "123@g.us",
					"participant": "111@s.whatsapp.net",
					"type": "read-self",
					"t": "1700000000"
				],
				content: .nodes([
					BinaryNode(tag: "list", content: .nodes([
						BinaryNode(tag: "item", attrs: ["id": "msg-2"])
					]))
				])
			),
			BinaryNode(
				tag: "receipt",
				attrs: [
					"id": "msg-3",
					"to": "123@g.us",
					"participant": "222@s.whatsapp.net",
					"type": "read-self",
					"t": "1700000000"
				]
			)
		])
	}

	@Test("readMessages uses read-self when privacy read receipts are limited")
	func readMessagesUsesReadSelfWhenPrivacyReadReceiptsAreLimited() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.readMessages([
				WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "msg-1")
			], timestampSeconds: 1_700_000_000)
		}
		let privacyRequest = try await transport.waitForSentNode(at: 0)
		try #require(privacyRequest.attrs["xmlns"] == "privacy")
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": privacyRequest.attrs["id"] ?? "", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "privacy", content: .nodes([
					BinaryNode(tag: "category", attrs: ["name": "readreceipts", "value": "none"])
				]))
			])
		))
		let receipt = try await transport.waitForSentNode(at: 1)
		try await task.value

		#expect(receipt == BinaryNode(
			tag: "receipt",
			attrs: ["id": "msg-1", "to": "123@s.whatsapp.net", "type": "read-self", "t": "1700000000"]
		))
	}

	@Test("sendReceipts groups keys with the requested receipt type")
	func sendReceiptsGroupsKeysWithRequestedReceiptType() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		try await client.sendReceipts([
			WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "msg-1"),
			WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "msg-2")
		], type: .played)

		let stanzas = try await sentNodes(from: transport)
		#expect(stanzas == [
			BinaryNode(
				tag: "receipt",
				attrs: ["id": "msg-1", "to": "123@s.whatsapp.net", "type": "played"],
				content: .nodes([
					BinaryNode(tag: "list", content: .nodes([
						BinaryNode(tag: "item", attrs: ["id": "msg-2"])
					]))
				])
			)
		])
	}

	@Test("sender receipts to user jids swap recipient and to attrs")
	func senderReceiptsToUserJIDsSwapRecipientAndToAttrs() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		try await client.sendReceipt(
			to: "123@s.whatsapp.net",
			participant: "456:1@s.whatsapp.net",
			messageIDs: ["msg-1"],
			type: .sender
		)

		let stanza = try await firstSentNode(from: transport)
		#expect(stanza == BinaryNode(
			tag: "receipt",
			attrs: ["id": "msg-1", "recipient": "123@s.whatsapp.net", "to": "456:1@s.whatsapp.net", "type": "sender"]
		))
	}
}

private func firstSentNode(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	try await sentNodes(from: transport)[0]
}

private func sentNodes(from transport: MockMessageSendWebSocketTransport) async throws -> [BinaryNode] {
	let frames = await transport.sentFrames
	var codec = NoiseFrameCodec()
	let decoder = BinaryNodeDecoder()
	return try frames.map { try decoder.decode(codec.decode($0)[0]) }
}

private func samplePresenceCredentials(name: String? = "Swift Bot") -> AuthenticationCredentials {
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
		me: WhatsAppUser(id: "999@s.whatsapp.net", name: name, lid: "999@lid"),
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true
	)
}
