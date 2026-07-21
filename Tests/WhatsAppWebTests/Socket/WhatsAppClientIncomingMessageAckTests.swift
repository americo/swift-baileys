import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client incoming message acknowledgements")
struct WhatsAppClientIncomingMessageAckTests {
	@Test("acknowledges successfully parsed incoming messages")
	func acknowledgesSuccessfullyParsedIncomingMessages() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let decryptor = MessageAckStubDecryptor(result: MessageContentBuilder.text("ack me"))
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: messageAckCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport },
			messageDecryptor: decryptor
		)
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "message",
			attrs: [
				"id": "incoming-ack-1",
				"from": "123@s.whatsapp.net",
				"type": "text"
			],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0x01])))
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "incoming-ack-1",
			from: "123@s.whatsapp.net",
			timestamp: nil,
			content: .text("ack me")
		)))
		#expect(try await firstMessageAck(from: transport) == BinaryNode(
			tag: "ack",
			attrs: [
				"id": "incoming-ack-1",
				"to": "123@s.whatsapp.net",
				"class": "message",
				"type": "text",
				"from": "999@s.whatsapp.net"
			]
		))
	}

	@Test("emits decryption failures without acknowledging the message")
	func emitsDecryptionFailuresWithoutAcknowledgingTheMessage() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: messageAckCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport },
			messageDecryptor: MessageAckThrowingDecryptor()
		)
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "message",
			attrs: [
				"id": "incoming-fail-1",
				"from": "123@s.whatsapp.net",
				"participant": "123:2@s.whatsapp.net",
				"t": "1700000000"
			],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0x01])))
			])
		))

		#expect(await events.next() == .messageDecryptionFailed(MessageDecryptionFailure(
			id: "incoming-fail-1",
			from: "123@s.whatsapp.net",
			participant: "123:2@s.whatsapp.net",
			timestamp: 1_700_000_000,
			ciphertextType: "msg",
			reason: .decryptionError("broken")
		)))
		#expect(await transport.sentFrames.isEmpty)
	}

	@Test("acknowledges and drops messages filtered by configuration")
	func acknowledgesAndDropsMessagesFilteredByConfiguration() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(
			configuration: WhatsAppClientConfiguration(shouldIgnoreJID: { $0 == "123@s.whatsapp.net" }),
			authenticationState: AuthenticationState(
				credentials: messageAckCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport },
			messageDecryptor: MessageAckStubDecryptor(result: MessageContentBuilder.text("ignored"))
		)
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "message",
			attrs: ["id": "ignored-msg-1", "from": "123@s.whatsapp.net", "type": "text"],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0x01])))
			])
		))

		#expect(try await firstMessageAck(from: transport) == BinaryNode(
			tag: "ack",
			attrs: [
				"id": "ignored-msg-1",
				"to": "123@s.whatsapp.net",
				"class": "message",
				"error": "500",
				"type": "text",
				"from": "999@s.whatsapp.net"
			]
		))
	}
}

private actor MessageAckStubDecryptor: IncomingMessageDecrypting {
	private let result: Proto_Message?

	init(result: Proto_Message?) {
		self.result = result
	}

	func decryptIncomingMessage(from node: BinaryNode) async throws -> Proto_Message? {
		result
	}
}

private struct MessageAckThrowingDecryptor: IncomingMessageDecrypting {
	func decryptIncomingMessage(from node: BinaryNode) async throws -> Proto_Message? {
		throw MessageAckDecryptorError.broken
	}
}

private enum MessageAckDecryptorError: Error {
	case broken
}

private func firstMessageAck(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	let frame = try #require(await transport.sentFrames.first)
	var codec = NoiseFrameCodec()
	return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
}

private func messageAckCredentials() -> AuthenticationCredentials {
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
		me: WhatsAppUser(id: "999@s.whatsapp.net", name: "Ack Bot", lid: "999@lid"),
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true
	)
}
