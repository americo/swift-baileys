import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client logout")
struct WhatsAppClientLogoutTests {
	@Test("sends remove companion device and disconnects")
	func sendsRemoveCompanionDeviceAndDisconnects() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: sampleLogoutCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		try await client.logout(reason: "User requested logout", requestID: "logout-1")

		let request = try await transport.waitForSentNode()
		#expect(request.tag == "iq")
		#expect(request.attrs["id"] == "logout-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "md")
		let remove = try #require(request.firstChild(named: "remove-companion-device"))
		#expect(remove.attrs["jid"] == "999@s.whatsapp.net")
		#expect(remove.attrs["reason"] == "user_initiated")
		#expect(await client.state == .disconnected)
	}
}

private func sampleLogoutCredentials() -> AuthenticationCredentials {
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
