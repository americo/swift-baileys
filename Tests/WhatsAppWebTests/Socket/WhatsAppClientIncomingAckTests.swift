import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client incoming ACKs")
struct WhatsAppClientIncomingAckTests {
	@Test("emits message error updates from message ACK errors")
	func emitsMessageErrorUpdatesFromMessageAckErrors() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "ack",
			attrs: [
				"class": "message",
				"from": "123@s.whatsapp.net",
				"id": "sent-msg-1",
				"error": "479"
			]
		))

		#expect(await events.next() == .messagesUpdated([
			ReceivedMessageUpdate(
				key: WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: true, id: "sent-msg-1"),
				status: .error,
				timestamp: nil
			)
		]))
	}

	@Test("does not emit updates for successful message ACKs")
	func doesNotEmitUpdatesForSuccessfulMessageAcks() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "ack",
			attrs: ["class": "message", "from": "123@s.whatsapp.net", "id": "sent-msg-1"]
		))

		await client.handleIncomingNode(BinaryNode(tag: "marker", attrs: ["id": "fallback"]))

		#expect(await events.next() == .message(BinaryNode(tag: "marker", attrs: ["id": "fallback"])))
	}

	@Test("issues trusted contact token after message account restriction ACK")
	func issuesTrustedContactTokenAfterMessageAccountRestrictionAck() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: sampleAckCredentials(), keys: InMemorySignalKeyStore()),
			transportFactory: { _ in transport },
			messageIDGenerator: MessageIDGenerator(
				unixTimestampSeconds: { 1_700_000_001 },
				randomBytes: { Data(repeating: 0x11, count: $0) }
			)
		)
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "ack",
			attrs: [
				"class": "message",
				"from": "123@s.whatsapp.net",
				"id": "sent-msg-463",
				"error": "463"
			]
		))

		#expect(await events.next() == .messagesUpdated([
			ReceivedMessageUpdate(
				key: WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: true, id: "sent-msg-463"),
				status: .error,
				timestamp: nil
			)
		]))
		try await Task.sleep(for: .milliseconds(25))
		let sentFrameCount = await transport.sentFrameCount()
		#expect(sentFrameCount == 1)
		guard sentFrameCount > 0 else {
			return
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "privacy")
		let token = try #require(request.firstChild(named: "tokens")?.firstChild(named: "token"))
		#expect(token.attrs["jid"] == "123@s.whatsapp.net")
		#expect(token.attrs["t"].flatMap(Int.init) != nil)
		#expect(token.attrs["type"] == "trusted_contact")
	}
}

private func sampleAckCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
		signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data([6])),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([8])),
			signature: Data([9]),
			keyID: 1
		),
		registrationID: 1,
		advSecretKey: "adv-secret",
		me: WhatsAppUser(id: "258840000000@s.whatsapp.net"),
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true
	)
}
