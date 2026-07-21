import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client pairing code")
struct WhatsAppClientPairingCodeTests {
	@Test("requests pairing code and stores updated credentials")
	func requestsPairingCodeAndStoresUpdatedCredentials() async throws {
		let transport = MockProfileWebSocketTransport()
		let credentials = samplePairingCodeCredentials()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: credentials, keys: InMemorySignalKeyStore()),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let code = try await client.requestPairingCode(
			forPhoneNumber: "258840000000",
			customPairingCode: "ABCDEFGH",
			requestID: "pair-code-1",
			salt: Data(1...32),
			iv: Data(33...48)
		)

		let request = try await transport.waitForSentNode()
		#expect(code == "ABCDEFGH")
		#expect(request.attrs["id"] == "pair-code-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "md")
		let registration = try #require(request.firstChild(named: "link_code_companion_reg"))
		#expect(registration.attrs["jid"] == "258840000000@s.whatsapp.net")
		#expect(registration.attrs["stage"] == "companion_hello")
		#expect(registration.attrs["should_show_push_notification"] == "true")
		#expect(registration.firstChild(named: "companion_server_auth_key_pub")?.content == .data(credentials.noiseKey.publicKey))
		#expect(registration.firstChild(named: "companion_platform_id")?.content == .data(Data("7".utf8)))
		#expect(registration.firstChild(named: "companion_platform_display")?.content == .data(Data("SwiftBaileys (macOS)".utf8)))
		#expect(registration.firstChild(named: "link_code_pairing_nonce")?.content == .data(Data("0".utf8)))
		let expectedWrappedKey = try hexData(
			"0102030405060708090a0b0c0d0e0f10" +
			"1112131415161718191a1b1c1d1e1f20" +
			"2122232425262728292a2b2c2d2e2f30" +
			"f5885140f0df903397e2ec120f148661" +
			"f54712d88988fb5406e83ae82de5f28d"
		)
		#expect(registration.firstChild(named: "link_code_pairing_wrapped_companion_ephemeral_pub")?.content == .data(expectedWrappedKey))

		let updated = try #require(await client.authenticationState?.credentials)
		#expect(updated.pairingCode == "ABCDEFGH")
		#expect(updated.me == WhatsAppUser(id: "258840000000@s.whatsapp.net", name: "~"))
	}

	@Test("rejects custom pairing codes that are not eight characters")
	func rejectsCustomPairingCodesThatAreNotEightCharacters() async throws {
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePairingCodeCredentials(),
				keys: InMemorySignalKeyStore()
			)
		)

		await #expect(throws: PairingCodeError.invalidCustomCodeLength) {
			try await client.requestPairingCode(
				forPhoneNumber: "258840000000",
				customPairingCode: "SHORT"
			)
		}
	}
}

private func samplePairingCodeCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(97...128)),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data(repeating: 2, count: 32), publicKey: Data(65...96)),
		signedIdentityKey: AuthenticationKeyPair(privateKey: Data(repeating: 3, count: 32), publicKey: Data(repeating: 4, count: 32)),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(privateKey: Data(repeating: 5, count: 32), publicKey: Data(repeating: 6, count: 32)),
			signature: Data(repeating: 7, count: 64),
			keyID: 1
		),
		registrationID: 559,
		advSecretKey: "adv-secret",
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: false
	)
}
