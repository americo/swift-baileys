import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Authentication credentials factory")
struct AuthenticationCredentialsFactoryTests {
	@Test("initializes credentials with Baileys defaults")
	func initializesCredentialsWithBaileysDefaults() throws {
		let generatedKeys = KeyPairSequence([
			AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32)),
			AuthenticationKeyPair(privateKey: Data(repeating: 3, count: 32), publicKey: Data(repeating: 4, count: 32)),
			AuthenticationKeyPair(privateKey: Data(repeating: 5, count: 32), publicKey: Data(repeating: 6, count: 32)),
			AuthenticationKeyPair(privateKey: Data(repeating: 7, count: 32), publicKey: Data(repeating: 8, count: 32))
		])
		let signedPayload = PayloadRecorder()
		let factory = AuthenticationCredentialsFactory(
			keyPairGenerator: { generatedKeys.next() },
			randomBytes: { count in Data(repeating: UInt8(count), count: count) },
			signer: { privateKey, payload in
				#expect(privateKey == Data(repeating: 1, count: 32))
				signedPayload.record(payload)
				return Data(repeating: 9, count: 64)
			}
		)

		let credentials = try factory.makeCredentials()

		#expect(credentials.signedIdentityKey == AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32)))
		#expect(credentials.noiseKey == AuthenticationKeyPair(privateKey: Data(repeating: 3, count: 32), publicKey: Data(repeating: 4, count: 32)))
		#expect(credentials.pairingEphemeralKeyPair == AuthenticationKeyPair(privateKey: Data(repeating: 5, count: 32), publicKey: Data(repeating: 6, count: 32)))
		#expect(credentials.signedPreKey.keyPair == AuthenticationKeyPair(privateKey: Data(repeating: 7, count: 32), publicKey: Data(repeating: 8, count: 32)))
		#expect(credentials.signedPreKey.keyID == 1)
		#expect(credentials.signedPreKey.signature == Data(repeating: 9, count: 64))
		#expect(signedPayload.value == Data([5]) + Data(repeating: 8, count: 32))
		#expect(credentials.registrationID == 514)
		#expect(credentials.advSecretKey == Data(repeating: 32, count: 32).base64EncodedString())
		#expect(credentials.nextPreKeyID == 1)
		#expect(credentials.firstUnuploadedPreKeyID == 1)
		#expect(credentials.accountSyncCounter == 0)
		#expect(credentials.accountSettings == AccountSettings(unarchiveChats: false))
		#expect(credentials.registered == false)
		#expect(credentials.pairingCode == nil)
		#expect(credentials.lastPropertyHash == nil)
		#expect(credentials.routingInfo == nil)
	}

	@Test("generates Curve25519 key pairs for production defaults")
	func generatesCurve25519KeyPairsForProductionDefaults() throws {
		let keyPair = try AuthenticationCredentialsFactory.makeCurve25519KeyPair()

		#expect(keyPair.privateKey.count == 32)
		#expect(keyPair.publicKey.count == 32)
	}

	@Test("rejects generated key pairs with invalid Curve25519 material")
	func rejectsGeneratedKeyPairsWithInvalidCurve25519Material() throws {
		let factory = AuthenticationCredentialsFactory(
			keyPairGenerator: { AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 31), publicKey: Data(repeating: 2, count: 32)) },
			randomBytes: { count in Data(repeating: UInt8(count), count: count) },
			signer: { _, _ in Data(repeating: 3, count: 64) }
		)

		#expect(throws: AuthenticationCredentialsFactoryError.invalidKeyPairMaterial) {
			_ = try factory.makeCredentials()
		}
	}

	@Test("masks registration id from two random bytes")
	func masksRegistrationIDFromTwoRandomBytes() throws {
		let factory = AuthenticationCredentialsFactory(
			keyPairGenerator: {
				AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32))
			},
			randomBytes: { count in count == 2 ? Data([0xff, 0xff]) : Data(repeating: 0, count: count) },
			signer: { _, _ in Data(repeating: 3, count: 64) }
		)

		#expect(try factory.makeCredentials().registrationID == 16_383)
	}

	@Test("rejects ADV secret random bytes with invalid length")
	func rejectsADVSecretRandomBytesWithInvalidLength() throws {
		let factory = AuthenticationCredentialsFactory(
			keyPairGenerator: {
				AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32))
			},
			randomBytes: { count in
				count == 32 ? Data(repeating: 0, count: 31) : Data(repeating: 0, count: count)
			},
			signer: { _, _ in Data(repeating: 3, count: 64) }
		)

		#expect(throws: AuthenticationCredentialsFactoryError.invalidRandomByteCount) {
			_ = try factory.makeCredentials()
		}
	}
}

private final class KeyPairSequence: @unchecked Sendable {
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

private final class PayloadRecorder: @unchecked Sendable {
	private let lock = NSLock()
	private var recordedValue: Data?

	var value: Data? {
		lock.withLock {
			recordedValue
		}
	}

	func record(_ value: Data) {
		lock.withLock {
			recordedValue = value
		}
	}
}
