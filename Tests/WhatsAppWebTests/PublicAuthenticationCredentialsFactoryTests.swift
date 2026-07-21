import Foundation
import Testing
import WhatsAppWeb

@Suite("Public authentication credentials factory")
struct PublicAuthenticationCredentialsFactoryTests {
	@Test("passes signed pre-key signature requests to the public signer")
	func passesSignedPreKeySignatureRequestsToPublicSigner() throws {
		let generatedKeys = PublicAuthenticationKeyPairSequence([
			AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32)),
			AuthenticationKeyPair(privateKey: Data(repeating: 3, count: 32), publicKey: Data(repeating: 4, count: 32)),
			AuthenticationKeyPair(privateKey: Data(repeating: 5, count: 32), publicKey: Data(repeating: 6, count: 32)),
			AuthenticationKeyPair(privateKey: Data(repeating: 7, count: 32), publicKey: Data(repeating: 8, count: 32))
		])
		let signedPreKeySigner = PublicSignedPreKeySigner(signature: Data(repeating: 9, count: 64))
		let factory = AuthenticationCredentialsFactory(
			keyPairGenerator: { generatedKeys.next() },
			randomBytes: { count in Data(repeating: UInt8(count), count: count) },
			signedPreKeySigner: signedPreKeySigner
		)

		let credentials = try factory.makeCredentials()

		#expect(credentials.signedPreKey.signature == Data(repeating: 9, count: 64))
		#expect(signedPreKeySigner.request == SignalSignedPreKeySignatureRequest(
			identityPrivateKey: Data(repeating: 1, count: 32),
			signedPreKeyPublicKey: Data(repeating: 8, count: 32)
		))
	}

	@Test("rejects invalid signed pre-key signatures from public signers")
	func rejectsInvalidSignedPreKeySignaturesFromPublicSigners() throws {
		let generatedKeys = PublicAuthenticationKeyPairSequence([
			AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32)),
			AuthenticationKeyPair(privateKey: Data(repeating: 3, count: 32), publicKey: Data(repeating: 4, count: 32)),
			AuthenticationKeyPair(privateKey: Data(repeating: 5, count: 32), publicKey: Data(repeating: 6, count: 32)),
			AuthenticationKeyPair(privateKey: Data(repeating: 7, count: 32), publicKey: Data(repeating: 8, count: 32))
		])
		let signedPreKeySigner = PublicSignedPreKeySigner(signature: Data(repeating: 9, count: 63))
		let factory = AuthenticationCredentialsFactory(
			keyPairGenerator: { generatedKeys.next() },
			randomBytes: { count in Data(repeating: UInt8(count), count: count) },
			signedPreKeySigner: signedPreKeySigner
		)

		#expect(throws: AuthenticationCredentialsFactoryError.invalidSignedPreKeySignature) {
			_ = try factory.makeCredentials()
		}
	}

	@Test("public signer readiness preflight validates ephemeral signed pre-key signatures")
	func publicSignerReadinessPreflightValidatesEphemeralSignedPreKeySignatures() throws {
		let validSigner = PublicSignedPreKeySigner(signature: Data(repeating: 9, count: 64))
		let invalidSigner = PublicSignedPreKeySigner(signature: Data(repeating: 9, count: 63))

		try validSigner.assertReadyForCredentialSigning()

		#expect(validSigner.request?.identityPrivateKey.count == 32)
		#expect(validSigner.request?.signedPreKeyPublicKey.count == 32)
		#expect(validSigner.request?.payload.count == 33)
		#expect(validSigner.request?.payload.first == 0x05)
		#expect(throws: SignalSignedPreKeySigningError.invalidSignedPreKeySignature) {
			try invalidSigner.assertReadyForCredentialSigning()
		}
	}
}

private final class PublicSignedPreKeySigner: SignalSignedPreKeySigning, @unchecked Sendable {
	private let lock = NSLock()
	private let signature: Data
	private var recordedRequest: SignalSignedPreKeySignatureRequest?

	init(signature: Data) {
		self.signature = signature
	}

	var request: SignalSignedPreKeySignatureRequest? {
		lock.withLock {
			recordedRequest
		}
	}

	func signSignedPreKey(_ request: SignalSignedPreKeySignatureRequest) throws -> Data {
		lock.withLock {
			recordedRequest = request
		}
		return signature
	}
}

private final class PublicAuthenticationKeyPairSequence: @unchecked Sendable {
	private let lock = NSLock()
	private var keyPairs: [AuthenticationKeyPair]

	init(_ keyPairs: [AuthenticationKeyPair]) {
		self.keyPairs = keyPairs
	}

	func next() -> AuthenticationKeyPair {
		lock.withLock {
			keyPairs.removeFirst()
		}
	}
}
