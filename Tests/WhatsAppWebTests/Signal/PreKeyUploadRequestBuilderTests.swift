import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Pre-key upload request builder")
struct PreKeyUploadRequestBuilderTests {
	@Test("accepts raw Curve25519 credential keys")
	func acceptsRawCurve25519CredentialKeys() throws {
		let request = try PreKeyUploadRequestBuilder.build(
			credentials: rawPreKeyUploadCredentials(),
			count: 1,
			requestID: "raw-pre-key-upload",
			keyPairGenerator: {
				AuthenticationKeyPair(
					privateKey: Data(repeating: 0x11, count: 32),
					publicKey: Data(repeating: 0x22, count: 32)
				)
			}
		)

		#expect(request.node.attrs["id"] == "raw-pre-key-upload")
		#expect(request.node.childData(named: "identity") == Data(repeating: 0x09, count: 32))
		let signedPreKey = try #require(request.node.firstChild(named: "skey"))
		#expect(signedPreKey.childData(named: "value") == Data(repeating: 0x08, count: 32))
		let preKey = try #require(request.node.firstChild(named: "list")?.firstChild(named: "key"))
		#expect(preKey.childData(named: "id") == Data([0, 0, 7]))
		#expect(preKey.childData(named: "value") == Data(repeating: 0x22, count: 32))
		#expect(request.nextPreKeyID == 8)
		#expect(request.firstUnuploadedPreKeyID == 8)
	}
}

private func rawPreKeyUploadCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
		signedIdentityKey: AuthenticationKeyPair(
			privateKey: Data([5]),
			publicKey: Data(repeating: 0x09, count: 32)
		),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(
				privateKey: Data([6]),
				publicKey: Data(repeating: 0x08, count: 32)
			),
			signature: Data(repeating: 0x07, count: 64),
			keyID: 1
		),
		registrationID: 559,
		advSecretKey: "adv-secret",
		me: WhatsAppUser(id: "258840000000@s.whatsapp.net"),
		nextPreKeyID: 7,
		firstUnuploadedPreKeyID: 7,
		accountSyncCounter: 0,
		registered: true
	)
}
