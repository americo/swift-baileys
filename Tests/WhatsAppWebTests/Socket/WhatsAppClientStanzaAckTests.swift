import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client stanza ACK")
struct WhatsAppClientStanzaAckTests {
	@Test("Baileys sendMessageAck alias sends ACK stanzas")
	func baileysSendMessageAckAliasSendsACKStanzas() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: ackCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let ack = try await client.sendMessageAck(BinaryNode(
			tag: "message",
			attrs: [
				"id": "msg-ack-public",
				"from": "123@s.whatsapp.net",
				"type": "text"
			]
		), errorCode: 500)

		let sent = try await transport.waitForSentNode()
		#expect(sent == ack)
		#expect(sent == BinaryNode(
			tag: "ack",
			attrs: [
				"id": "msg-ack-public",
				"to": "123@s.whatsapp.net",
				"class": "message",
				"error": "500",
				"type": "text",
				"from": "999@s.whatsapp.net"
			]
		))
	}

	@Test("sendMessageAck rejects stanzas without ack ids")
	func sendMessageAckRejectsStanzasWithoutACKIDs() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		await #expect(throws: WhatsAppClientError.missingRequestID) {
			try await client.sendMessageAck(BinaryNode(
				tag: "receipt",
				attrs: ["from": "123@s.whatsapp.net"]
			))
		}
	}
}

private func ackCredentials() -> AuthenticationCredentials {
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
