import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client message relay alias")
struct WhatsAppClientMessageRelayAliasTests {
	@Test("Baileys relayMessage alias sends direct protobuf messages")
	func baileysRelayMessageAliasSendsDirectProtobufMessages() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: StubMessageSendEncryptor(
				results: [EncryptedMessage(type: "msg", ciphertext: Data([0x10]))],
				callOrder: callOrder
			),
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123:0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		let messageID = try await client.relayMessage(
			to: "123@s.whatsapp.net",
			encodedMessage: MessageContentBuilder.text("relay hello").serializedData(),
			options: BaileysMessageRelayOptions(
				messageID: "3EB0RELAY",
				additionalAttributes: ["category": "peer"],
				additionalNodes: [BinaryNode(tag: "meta", attrs: ["appdata": "default"])]
			)
		)

		#expect(messageID == "3EB0RELAY")
		let stanza = try await sentMessageNode(from: transport, at: 0)
		#expect(stanza.attrs["id"] == "3EB0RELAY")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
		#expect(stanza.attrs["category"] == "peer")
		#expect(stanza.firstChild(named: "meta")?.attrs["appdata"] == "default")
		#expect(stanza.firstChild(named: "participants")?.firstChild(named: "to")?.attrs["jid"] == "123:0@s.whatsapp.net")
	}

	@Test("Baileys relayMessage participant option sends retry stanza to participant")
	func baileysRelayMessageParticipantOptionSendsRetryStanzaToParticipant() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: StubMessageSendEncryptor(
				results: [EncryptedMessage(type: "msg", ciphertext: Data([0x22]))]
			),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		let messageID = try await client.relayMessage(
			to: "123@g.us",
			encodedMessage: MessageContentBuilder.text("retry hello").serializedData(),
			options: BaileysMessageRelayOptions(
				messageID: "3EB0RELAYRETRY",
				participant: BaileysMessageRelayParticipant(jid: "456:1@s.whatsapp.net", count: 2),
				additionalAttributes: ["edit": "7"],
				additionalNodes: [BinaryNode(tag: "meta", attrs: ["retry": "true"])]
			)
		)

		#expect(messageID == "3EB0RELAYRETRY")
		let stanza = try await sentMessageNode(from: transport, at: 0)
		#expect(stanza.attrs["id"] == "3EB0RELAYRETRY")
		#expect(stanza.attrs["to"] == "123@g.us")
		#expect(stanza.attrs["participant"] == "456:1@s.whatsapp.net")
		#expect(stanza.attrs["edit"] == "7")
		let enc = try #require(stanza.firstChild(named: "enc"))
		#expect(enc.attrs["count"] == "2")
		#expect(enc.content == .data(Data([0x22])))
		#expect(stanza.firstChild(named: "meta")?.attrs["retry"] == "true")
	}

	@Test("Baileys relayMessage forwards user device cache option")
	func baileysRelayMessageForwardsUserDeviceCacheOption() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let resolver = CacheAwareRelayDeviceResolver(result: ["123:0@s.whatsapp.net"])
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: StubMessageSendEncryptor(
				results: [EncryptedMessage(type: "msg", ciphertext: Data([0x33]))]
			),
			messageDeviceResolver: resolver,
			signalSessionPreparer: PublicSessionPreparer(),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.relayMessage(
			to: "123@s.whatsapp.net",
			encodedMessage: MessageContentBuilder.text("fresh devices").serializedData(),
			options: BaileysMessageRelayOptions(
				messageID: "3EB0RELAYCACHE",
				useUserDevicesCache: false
			)
		)

		#expect(await resolver.calls == [
			RelayDeviceResolutionCall(jid: "123@s.whatsapp.net", useCache: false)
		])
	}

	@Test("Baileys relayMessage status list sends sender-key stanza to broadcast")
	func baileysRelayMessageStatusListSendsSenderKeyStanzaToBroadcast() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let groupEncryptor = AliasGroupMessageEncryptor(result: EncryptedGroupMessage(
			ciphertext: Data([0xaa]),
			senderKeyDistributionMessage: Data([0xbb])
		))
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: relayAliasCredentials(), keys: InMemorySignalKeyStore()),
			transportFactory: { _ in transport },
			messageEncryptor: StubMessageSendEncryptor(
				results: [EncryptedMessage(type: "pkmsg", ciphertext: Data([0x44]))]
			),
			groupMessageEncryptor: groupEncryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["111:0@s.whatsapp.net"]),
			signalSessionPreparer: PublicSessionPreparer(),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		let messageID = try await client.relayMessage(
			to: "status@broadcast",
			encodedMessage: MessageContentBuilder.text("status hello").serializedData(),
			options: BaileysMessageRelayOptions(
				messageID: "3EB0STATUS",
				additionalAttributes: ["edit": "0"],
				statusJidList: ["111@s.whatsapp.net"]
			)
		)

		#expect(messageID == "3EB0STATUS")
		#expect(await groupEncryptor.calls.map(\.group) == ["status@broadcast"])
		let stanza = try await sentMessageNode(from: transport, at: 0)
		#expect(stanza.attrs["id"] == "3EB0STATUS")
		#expect(stanza.attrs["to"] == "status@broadcast")
		#expect(stanza.attrs["edit"] == "0")
		#expect(stanza.firstChild(named: "participants")?.firstChild(named: "to")?.attrs["jid"] == "111:0@s.whatsapp.net")
		#expect(stanza.firstChild(named: "enc")?.attrs["type"] == "skmsg")
		#expect(stanza.firstChild(named: "enc")?.content == .data(Data([0xaa])))
	}

	private func sentMessageNode(from transport: MockMessageSendWebSocketTransport, at index: Int) async throws -> BinaryNode {
		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[index])
		return try BinaryNodeDecoder().decode(frames[0])
	}
}

private actor AliasGroupMessageEncryptor: GroupMessageEncrypting {
	private let result: EncryptedGroupMessage
	private(set) var calls: [AliasGroupMessageEncryptionCall] = []

	init(result: EncryptedGroupMessage) {
		self.result = result
	}

	func encryptGroupMessage(group: String, senderJID: String, data: Data) async throws -> EncryptedGroupMessage {
		calls.append(AliasGroupMessageEncryptionCall(group: group, senderJID: senderJID, data: data))
		return result
	}
}

private struct AliasGroupMessageEncryptionCall: Equatable, Sendable {
	let group: String
	let senderJID: String
	let data: Data
}

private actor CacheAwareRelayDeviceResolver: MessageDeviceResolving {
	private let result: [String]
	private(set) var calls: [RelayDeviceResolutionCall] = []

	init(result: [String]) {
		self.result = result
	}

	func deviceJIDs(for jid: String) async throws -> [String] {
		try await deviceJIDs(for: jid, useCache: true)
	}

	func deviceJIDs(for jid: String, useCache: Bool) async throws -> [String] {
		calls.append(RelayDeviceResolutionCall(jid: jid, useCache: useCache))
		return result
	}
}

private struct RelayDeviceResolutionCall: Equatable, Sendable {
	let jid: String
	let useCache: Bool
}

private func relayAliasCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32)),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data(repeating: 3, count: 32), publicKey: Data(repeating: 4, count: 32)),
		signedIdentityKey: AuthenticationKeyPair(privateKey: Data(repeating: 5, count: 32), publicKey: Data(repeating: 6, count: 32)),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(privateKey: Data(repeating: 7, count: 32), publicKey: Data(repeating: 8, count: 32)),
			signature: Data(repeating: 9, count: 64),
			keyID: 1
		),
		registrationID: 1,
		advSecretKey: "adv-secret",
		me: WhatsAppUser(id: "999@s.whatsapp.net", lid: "999@lid"),
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true
	)
}
