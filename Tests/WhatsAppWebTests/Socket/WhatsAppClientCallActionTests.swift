import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client call actions")
struct WhatsAppClientCallActionTests {
	@Test("rejects calls with Baileys-compatible call stanza")
	func rejectsCallsWithBaileysCompatibleCallStanza() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: callActionCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		try await client.rejectCall(id: "call-1", from: "123@s.whatsapp.net")

		let stanza = try await firstCallActionNode(from: transport)
		#expect(stanza == BinaryNode(
			tag: "call",
			attrs: ["from": "999@s.whatsapp.net", "to": "123@s.whatsapp.net"],
			content: .nodes([
				BinaryNode(
					tag: "reject",
					attrs: ["call-id": "call-1", "call-creator": "123@s.whatsapp.net", "count": "0"]
				)
			])
		))
	}
}

private func firstCallActionNode(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	let frame = try #require(await transport.sentFrames.first)
	var codec = NoiseFrameCodec()
	return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
}

private func callActionCredentials() -> AuthenticationCredentials {
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
		me: WhatsAppUser(id: "999@s.whatsapp.net", name: "Swift Bot"),
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true
	)
}
