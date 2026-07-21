import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Signal signed key pair factory")
struct SignalSignedKeyPairFactoryTests {
	@Test("generates a raw pre-key and signs the formatted public key")
	func generatesRawPreKeyAndSignsFormattedPublicKey() throws {
		let signedPayload = SignalSignedKeyPairPayloadRecorder()
		let signedKeyPair = try SignalSignedKeyPairFactory.make(
			identityKeyPair: AuthenticationKeyPair(
				privateKey: Data(repeating: 0x01, count: 32),
				publicKey: Data(repeating: 0x02, count: 32)
			),
			keyID: 7,
			keyPairGenerator: {
				AuthenticationKeyPair(
					privateKey: Data(repeating: 0x03, count: 32),
					publicKey: Data(repeating: 0x04, count: 32)
				)
			},
			signer: { request in
				signedPayload.record(request)
				return Data(repeating: 0x09, count: 64)
			}
		)

		#expect(signedKeyPair.keyPair == AuthenticationKeyPair(
			privateKey: Data(repeating: 0x03, count: 32),
			publicKey: Data(repeating: 0x04, count: 32)
		))
		#expect(signedKeyPair.keyID == 7)
		#expect(signedKeyPair.signature == Data(repeating: 0x09, count: 64))
		#expect(signedPayload.request == SignalSignedPreKeySignatureRequest(
			identityPrivateKey: Data(repeating: 0x01, count: 32),
			signedPreKeyPublicKey: Data(repeating: 0x04, count: 32)
		))
		#expect(signedPayload.request?.payload == Data([0x05]) + Data(repeating: 0x04, count: 32))
	}

	@Test("rejects invalid identity key material")
	func rejectsInvalidIdentityKeyMaterial() {
		#expect(throws: SignalSignedKeyPairFactoryError.invalidKeyPairMaterial) {
			_ = try SignalSignedKeyPairFactory.make(
				identityKeyPair: AuthenticationKeyPair(
					privateKey: Data(repeating: 0x01, count: 31),
					publicKey: Data(repeating: 0x02, count: 32)
				),
				keyID: 1,
				keyPairGenerator: {
					AuthenticationKeyPair(
						privateKey: Data(repeating: 0x03, count: 32),
						publicKey: Data(repeating: 0x04, count: 32)
					)
				},
				signer: { _ in Data(repeating: 0x09, count: 64) }
			)
		}
	}

	@Test("rejects invalid signed pre-key material")
	func rejectsInvalidSignedPreKeyMaterial() {
		#expect(throws: SignalSignedKeyPairFactoryError.invalidKeyPairMaterial) {
			_ = try SignalSignedKeyPairFactory.make(
				identityKeyPair: AuthenticationKeyPair(
					privateKey: Data(repeating: 0x01, count: 32),
					publicKey: Data(repeating: 0x02, count: 32)
				),
				keyID: 1,
				keyPairGenerator: {
					AuthenticationKeyPair(
						privateKey: Data(repeating: 0x03, count: 32),
						publicKey: Data(repeating: 0x04, count: 31)
					)
				},
				signer: { _ in Data(repeating: 0x09, count: 64) }
			)
		}
	}

	@Test("rejects invalid signatures")
	func rejectsInvalidSignatures() {
		#expect(throws: SignalSignedKeyPairFactoryError.invalidSignature) {
			_ = try SignalSignedKeyPairFactory.make(
				identityKeyPair: AuthenticationKeyPair(
					privateKey: Data(repeating: 0x01, count: 32),
					publicKey: Data(repeating: 0x02, count: 32)
				),
				keyID: 1,
				keyPairGenerator: {
					AuthenticationKeyPair(
						privateKey: Data(repeating: 0x03, count: 32),
						publicKey: Data(repeating: 0x04, count: 32)
					)
				},
				signer: { _ in Data(repeating: 0x09, count: 63) }
			)
		}
	}
}

private final class SignalSignedKeyPairPayloadRecorder: @unchecked Sendable {
	private let lock = NSLock()
	private var recordedRequest: SignalSignedPreKeySignatureRequest?

	var request: SignalSignedPreKeySignatureRequest? {
		lock.withLock {
			recordedRequest
		}
	}

	func record(_ request: SignalSignedPreKeySignatureRequest) {
		lock.withLock {
			recordedRequest = request
		}
	}
}
