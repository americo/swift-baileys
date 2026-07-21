import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client trusted-contact token prune")
struct WhatsAppClientTrustedContactTokenPruneTests {
	@Test("connect prunes expired trusted contact tokens from the persisted index")
	func connectPrunesExpiredTrustedContactTokensFromPersistedIndex() async throws {
		let expiredJID = "258840000001@s.whatsapp.net"
		let validJID = "258840000002@s.whatsapp.net"
		let keys = InMemorySignalKeyStore(storage: [
			.tcToken: [
				TrustedContactTokenCoding.indexKey: try TrustedContactTokenCoding.encodeIndex([
					expiredJID,
					validJID
				]),
				expiredJID: try TrustedContactTokenCoding.encode(TrustedContactToken(
					token: Data([0x01]),
					timestamp: "1"
				)),
				validJID: try TrustedContactTokenCoding.encode(TrustedContactToken(
					token: Data([0x02]),
					timestamp: String(Int(Date().timeIntervalSince1970))
				))
			]
		])
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: samplePruneCredentials(), keys: keys),
			transportFactory: { _ in MockProfileWebSocketTransport() }
		)

		try await client.connect()

		let entries = try await keys.get(.tcToken, ids: [
			TrustedContactTokenCoding.indexKey,
			expiredJID,
			validJID
		])
		#expect(entries[expiredJID] == nil)
		#expect(try TrustedContactTokenCoding.decodeIndex(entries[TrustedContactTokenCoding.indexKey]) == [validJID])
		#expect(entries[validJID] != nil)
	}
}

private func samplePruneCredentials() -> AuthenticationCredentials {
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
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true
	)
}
