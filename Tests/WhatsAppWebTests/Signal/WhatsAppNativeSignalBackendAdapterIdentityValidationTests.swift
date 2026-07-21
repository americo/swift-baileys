import Foundation
import Testing
import WhatsAppWeb

@Suite("WhatsApp native Signal backend adapter identity validation")
struct WhatsAppNativeSignalBackendAdapterIdentityValidationTests {
	@Test("rejects mismatched native account identities before backend account calls")
	func rejectsMismatchedNativeAccountIdentitiesBeforeBackendAccountCalls() async throws {
		let backend = IdentityValidationBackend()
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: backend)
		let request = SignalNativeAccountImportRequest(
			localJID: "999:0@s.whatsapp.net",
			localAddress: SignalProtocolAddress(name: "123", deviceID: 0),
			keyMaterial: SignalNativeAccountKeyMaterial(
				registrationID: 1,
				identityPrivateKey: Data([0x01]),
				identityCurve25519PublicKey: Data(repeating: 0x02, count: 32),
				signedPreKeyID: 2,
				signedPreKeyPrivateKey: Data([0x03]),
				signedPreKeyCurve25519PublicKey: Data(repeating: 0x04, count: 32),
				signedPreKeySignature: Data(repeating: 0x05, count: 64)
			)
		)

		await #expect(throws: SignalNativeKeyMaterialError.invalidLocalJID) {
			try await adapter.importAccount(request)
		}
		await #expect(throws: SignalNativeKeyMaterialError.invalidLocalJID) {
			_ = try await adapter.containsAccount(request)
		}
		#expect(await backend.importCount == 0)
		#expect(await backend.checkCount == 0)
	}

	@Test("rejects mismatched native pre-key upload identities before backend upload")
	func rejectsMismatchedNativePreKeyUploadIdentitiesBeforeBackendUpload() async throws {
		let backend = IdentityValidationBackend()
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: backend)
		let request = SignalNativePreKeyUploadRequest(
			localJID: "999:0@s.whatsapp.net",
			localAddress: SignalProtocolAddress(name: "123", deviceID: 0),
			currentServerPreKeyCount: 1,
			registrationID: 1,
			identityPrivateKey: Data([0x01]),
			identityCurve25519PublicKey: Data(repeating: 0x02, count: 32),
			signedPreKeyID: 2,
			signedPreKeyPrivateKey: Data([0x03]),
			signedPreKeyCurve25519PublicKey: Data(repeating: 0x04, count: 32),
			signedPreKeySignature: Data(repeating: 0x05, count: 64),
			firstUnuploadedPreKeyID: 10,
			requestedUploadCount: 2
		)

		await #expect(throws: SignalNativePreKeyUploadRequestError.invalidLocalJID) {
			try await adapter.uploadPreKeys(SignalPreKeyUploadRequest(
				currentCount: 1,
				requestedUploadCount: 2,
				nativeUploadRequest: request
			))
		}
		#expect(await backend.preKeyUploadCount == 0)
	}
}

private actor IdentityValidationBackend: WhatsAppNativeSignalBackend {
	private(set) var importCount = 0
	private(set) var checkCount = 0
	private(set) var preKeyUploadCount = 0

	nonisolated func signSignedPreKey(identityPrivateKey: Data, signedPreKeyPublicKey: Data) throws -> Data {
		Data(repeating: 0x51, count: 64)
	}

	func assertReadyForSignalOperations() async throws {}

	func importAccount(_ account: WhatsAppNativeSignalAccount) async throws {
		importCount += 1
	}

	func containsAccount(_ account: WhatsAppNativeSignalAccount) async throws -> Bool {
		checkCount += 1
		return false
	}

	func existingSessions(for checks: [SignalSessionAddressCheck]) async throws -> Set<SignalProtocolAddress> {
		[]
	}

	func installSession(_ session: WhatsAppNativeSignalSession) async throws {}

	func encryptDirectMessage(_ message: WhatsAppNativeDirectMessage) async throws -> WhatsAppNativeDirectCiphertext {
		WhatsAppNativeDirectCiphertext(type: .signalMessage, ciphertext: Data([0x01]))
	}

	func encryptGroupMessage(_ message: WhatsAppNativeGroupMessage) async throws -> WhatsAppNativeGroupCiphertext {
		WhatsAppNativeGroupCiphertext(ciphertext: Data([0x01]), senderKeyDistributionMessage: Data([0x02]))
	}

	func decryptDirectMessage(_ message: WhatsAppNativeDirectCiphertextMessage) async throws -> Data {
		Data([0x01])
	}

	func decryptGroupMessage(_ message: WhatsAppNativeGroupCiphertextMessage) async throws -> Data {
		Data([0x01])
	}

	func processSenderKeyDistributionMessage(_ message: WhatsAppNativeSenderKeyDistributionMessage) async throws {}

	func uploadPreKeys(_ request: SignalNativePreKeyUploadRequest) async throws {
		preKeyUploadCount += 1
	}
}
