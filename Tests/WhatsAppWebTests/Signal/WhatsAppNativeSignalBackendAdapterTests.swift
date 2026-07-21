import Foundation
import Testing
import WhatsAppWeb

@Suite("WhatsApp native Signal backend adapter")
struct WhatsAppNativeSignalBackendAdapterTests {
	@Test("delegates native Signal operations through validated request types")
	func delegatesNativeSignalOperations() async throws {
		let backend = RecordingWhatsAppNativeSignalBackend(existingAddresses: [
			SignalProtocolAddress(name: "123", deviceID: 0)
		])
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: backend)
		let directRequest = try SignalDirectMessageEncryptionRequest(
			jid: "123:1@s.whatsapp.net",
			localJID: "999:0@s.whatsapp.net",
			data: Data([0xaa])
		)
		let groupRequest = try SignalGroupMessageEncryptionRequest(
			groupJID: "111-222@g.us",
			senderJID: "999:0@s.whatsapp.net",
			data: Data([0xbb])
		)
		let directDecryptRequest = try SignalDirectMessageDecryptionRequest(
			jid: "123:1@s.whatsapp.net",
			ciphertextType: .signalMessage,
			localJID: "999:0@s.whatsapp.net",
			ciphertext: Data([0xcc])
		)
		let groupDecryptRequest = try SignalGroupMessageDecryptionRequest(
			groupJID: "111-222@g.us",
			authorJID: "123:1@s.whatsapp.net",
			ciphertext: Data([0xdd])
		)
		let distributionRequest = try SenderKeyDistributionMessageRequest(
			authorJID: "123:1@s.whatsapp.net",
			groupJID: "111-222@g.us",
			senderKeyDistributionData: Data([0xed]),
			messageData: Data([0xee])
		)
		let installRequest = SignalSessionNativeInstallRequest(
			jid: "123:1@s.whatsapp.net",
			address: SignalProtocolAddress(name: "123", deviceID: 1),
			localJID: "999:0@s.whatsapp.net",
			localAddress: SignalProtocolAddress(name: "999", deviceID: 0),
			registrationID: 7,
			identityCurve25519PublicKey: Data(repeating: 1, count: 32),
			signedPreKeyID: 8,
			signedPreKeyCurve25519PublicKey: Data(repeating: 2, count: 32),
			signedPreKeySignature: Data(repeating: 3, count: 64),
			preKeyID: 9,
			preKeyCurve25519PublicKey: Data(repeating: 4, count: 32)
		)
		let accountRequest = SignalNativeAccountImportRequest(
			localJID: "999:0@s.whatsapp.net",
			localAddress: SignalProtocolAddress(name: "999", deviceID: 0),
			keyMaterial: SignalNativeAccountKeyMaterial(
				registrationID: 1,
				identityPrivateKey: Data([0x01]),
				identityCurve25519PublicKey: Data(repeating: 0x02, count: 32),
				signedPreKeyID: 2,
				signedPreKeyPrivateKey: Data([0x03]),
				signedPreKeyCurve25519PublicKey: Data(repeating: 0x04, count: 32),
				signedPreKeySignature: Data(repeating: 5, count: 64)
			)
		)
		let preKeyUploadRequest = SignalNativePreKeyUploadRequest(
			localJID: "999:0@s.whatsapp.net",
			localAddress: SignalProtocolAddress(name: "999", deviceID: 0),
			currentServerPreKeyCount: 1,
			registrationID: 1,
			identityPrivateKey: Data([0x01]),
			identityCurve25519PublicKey: Data(repeating: 0x02, count: 32),
			signedPreKeyID: 2,
			signedPreKeyPrivateKey: Data([0x03]),
			signedPreKeyCurve25519PublicKey: Data(repeating: 0x04, count: 32),
			signedPreKeySignature: Data(repeating: 5, count: 64),
			firstUnuploadedPreKeyID: 10,
			requestedUploadCount: 2
		)

		let signature = try adapter.signSignedPreKey(SignalSignedPreKeySignatureRequest(
			identityPrivateKey: Data([0x11]),
			signedPreKeyPublicKey: Data([0x12])
		))
		try await adapter.assertReadyForSignalOperations()
		try await adapter.importAccount(accountRequest)
		let containsAccount = try await adapter.containsAccount(accountRequest)
		let existingSessions = try await adapter.existingSessions(for: [
			SignalSessionAddressCheck(jid: "123:0@s.whatsapp.net", address: SignalProtocolAddress(name: "123", deviceID: 0)),
			SignalSessionAddressCheck(jid: "123:1@s.whatsapp.net", address: SignalProtocolAddress(name: "123", deviceID: 1))
		])
		try await adapter.installSession(installRequest)
		let encrypted = try await adapter.encryptMessage(directRequest)
		let groupEncrypted = try await adapter.encryptGroupMessage(groupRequest)
		let decrypted = try await adapter.decryptMessage(directDecryptRequest)
		let groupDecrypted = try await adapter.decryptGroupMessage(groupDecryptRequest)
		try await adapter.processSenderKeyDistributionMessage(distributionRequest)
		try await adapter.uploadPreKeys(SignalPreKeyUploadRequest(
			currentCount: 1,
			requestedUploadCount: 2,
			nativeUploadRequest: preKeyUploadRequest
		))

		#expect(signature == Data(repeating: 0x51, count: 64))
		#expect(await backend.readinessCheckCount == 1)
		#expect(containsAccount)
		#expect(existingSessions == [SignalProtocolAddress(name: "123", deviceID: 0)])
		#expect(encrypted == EncryptedMessage(ciphertextType: .signalMessage, ciphertext: Data([0xaa, 0x01])))
		#expect(groupEncrypted == EncryptedGroupMessage(ciphertext: Data([0xbb, 0x02]), senderKeyDistributionMessage: Data([0x21])))
		#expect(decrypted == Data([0xcc, 0x03]))
		#expect(groupDecrypted == Data([0xdd, 0x04]))
		#expect(await backend.importedAccounts.map(\.address) == [SignalProtocolAddress(name: "999", deviceID: 0)])
		#expect(await backend.importedAccounts.map(\.localJID) == ["999:0@s.whatsapp.net"])
		#expect(await backend.accountChecks.map(\.address) == [SignalProtocolAddress(name: "999", deviceID: 0)])
		#expect(await backend.accountChecks.map(\.localJID) == ["999:0@s.whatsapp.net"])
		#expect(await backend.sessionChecks == [[
			SignalSessionAddressCheck(jid: "123:0@s.whatsapp.net", address: SignalProtocolAddress(name: "123", deviceID: 0)),
			SignalSessionAddressCheck(jid: "123:1@s.whatsapp.net", address: SignalProtocolAddress(name: "123", deviceID: 1))
		]])
		#expect(await backend.installedSessions.map(\.request) == [installRequest])
		#expect(await backend.installedSessions.map(\.jid) == ["123:1@s.whatsapp.net"])
		#expect(await backend.installedSessions.map(\.localJID) == ["999:0@s.whatsapp.net"])
		#expect(await backend.installedSessions.map(\.preKeyID) == [9])
		#expect(await backend.directMessages.map(\.jid) == ["123:1@s.whatsapp.net"])
		#expect(await backend.directMessages.map(\.localJID) == ["999:0@s.whatsapp.net"])
		#expect(await backend.directMessages.map(\.remoteAddress) == [SignalProtocolAddress(name: "123", deviceID: 1)])
		#expect(await backend.directMessages.map(\.localAddress) == [SignalProtocolAddress(name: "999", deviceID: 0)])
		#expect(await backend.groupMessages.map(\.senderJID) == ["999:0@s.whatsapp.net"])
		#expect(await backend.groupMessages.map(\.senderAddress) == [SignalProtocolAddress(name: "999", deviceID: 0)])
		#expect(await backend.directCiphertextMessages.map(\.jid) == ["123:1@s.whatsapp.net"])
		#expect(await backend.directCiphertextMessages.map(\.localJID) == ["999:0@s.whatsapp.net"])
		#expect(await backend.directCiphertextMessages.map(\.ciphertextType) == [.signalMessage])
		#expect(await backend.directCiphertextMessages.map(\.type) == [.signalMessage])
		#expect(await backend.groupCiphertextMessages.map(\.authorJID) == ["123:1@s.whatsapp.net"])
		#expect(await backend.groupCiphertextMessages.map(\.authorAddress) == [SignalProtocolAddress(name: "123", deviceID: 1)])
		#expect(await backend.senderKeyMessages.map(\.groupJID) == ["111-222@g.us"])
		#expect(await backend.senderKeyMessages.map(\.authorJID) == ["123:1@s.whatsapp.net"])
		#expect(await backend.senderKeyMessages.map(\.senderKeyDistributionData) == [Data([0xed])])
		#expect(await backend.senderKeyMessages.map(\.messageData) == [Data([0xee])])
		#expect(await backend.preKeyUploads == [preKeyUploadRequest])
		#expect(await backend.preKeyUploads.map(\.localJID) == ["999:0@s.whatsapp.net"])
		#expect(await backend.preKeyUploads.map(\.localAddress) == [SignalProtocolAddress(name: "999", deviceID: 0)])
		#expect(await backend.preKeyUploads.map(\.currentServerPreKeyCount) == [1])
	}

	@Test("rejects pre-key upload without native upload material")
	func rejectsPreKeyUploadWithoutNativeMaterial() async throws {
		let backend = RecordingWhatsAppNativeSignalBackend(existingAddresses: [])
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: backend)

		await #expect(throws: WhatsAppNativeSignalBackendAdapterError.missingNativePreKeyUploadRequest) {
			try await adapter.uploadPreKeys(SignalPreKeyUploadRequest(requestedUploadCount: 2))
		}
	}

	@Test("rejects invalid signed pre-key signatures before credentials use them")
	func rejectsInvalidSignedPreKeySignaturesBeforeCredentialsUseThem() throws {
		let backend = RecordingWhatsAppNativeSignalBackend(
			existingAddresses: [],
			signedPreKeySignature: Data(repeating: 0x51, count: 63)
		)
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: backend)

		#expect(throws: WhatsAppNativeSignalBackendAdapterError.invalidSignedPreKeySignature) {
			_ = try adapter.signSignedPreKey(SignalSignedPreKeySignatureRequest(
				identityPrivateKey: Data([0x11]),
				signedPreKeyPublicKey: Data(repeating: 0x12, count: 32)
			))
		}
	}

	@Test("rejects invalid native account key material before backend import")
	func rejectsInvalidNativeAccountKeyMaterialBeforeBackendImport() async throws {
		let backend = RecordingWhatsAppNativeSignalBackend(existingAddresses: [])
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: backend)
		let request = SignalNativeAccountImportRequest(
			localJID: "999:0@s.whatsapp.net",
			localAddress: SignalProtocolAddress(name: "999", deviceID: 0),
			keyMaterial: SignalNativeAccountKeyMaterial(
				registrationID: 1,
				identityPrivateKey: Data([0x01]),
				identityCurve25519PublicKey: Data(repeating: 2, count: 31),
				signedPreKeyID: 3,
				signedPreKeyPrivateKey: Data([0x04]),
				signedPreKeyCurve25519PublicKey: Data(repeating: 5, count: 32),
				signedPreKeySignature: Data(repeating: 6, count: 64)
			)
		)

		await #expect(throws: SignalNativeKeyMaterialError.invalidKeyMaterial) {
			try await adapter.importAccount(request)
		}
		await #expect(throws: SignalNativeKeyMaterialError.invalidKeyMaterial) {
			_ = try await adapter.containsAccount(request)
		}
		#expect(await backend.importedAccounts.isEmpty)
		#expect(await backend.accountChecks.isEmpty)
	}

	@Test("rejects invalid native account signed pre-key IDs before backend import")
	func rejectsInvalidNativeAccountSignedPreKeyIDsBeforeBackendImport() async throws {
		let backend = RecordingWhatsAppNativeSignalBackend(existingAddresses: [])
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: backend)
		let request = SignalNativeAccountImportRequest(
			localJID: "999:0@s.whatsapp.net",
			localAddress: SignalProtocolAddress(name: "999", deviceID: 0),
			keyMaterial: SignalNativeAccountKeyMaterial(
				registrationID: 1,
				identityPrivateKey: Data([0x01]),
				identityCurve25519PublicKey: Data(repeating: 2, count: 32),
				signedPreKeyID: 0,
				signedPreKeyPrivateKey: Data([0x04]),
				signedPreKeyCurve25519PublicKey: Data(repeating: 5, count: 32),
				signedPreKeySignature: Data(repeating: 6, count: 64)
			)
		)

		await #expect(throws: SignalNativeKeyMaterialError.invalidKeyID) {
			try await adapter.importAccount(request)
		}
		await #expect(throws: SignalNativeKeyMaterialError.invalidKeyID) {
			_ = try await adapter.containsAccount(request)
		}
		#expect(await backend.importedAccounts.isEmpty)
		#expect(await backend.accountChecks.isEmpty)
	}

	@Test("rejects invalid native pre-key upload material before backend upload")
	func rejectsInvalidNativePreKeyUploadMaterialBeforeBackendUpload() async throws {
		let backend = RecordingWhatsAppNativeSignalBackend(existingAddresses: [])
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: backend)
		let request = SignalNativePreKeyUploadRequest(
			registrationID: 1,
			identityPrivateKey: Data([0x01]),
			identityCurve25519PublicKey: Data(repeating: 2, count: 32),
			signedPreKeyID: 3,
			signedPreKeyPrivateKey: Data([0x04]),
			signedPreKeyCurve25519PublicKey: Data(repeating: 5, count: 31),
			signedPreKeySignature: Data(repeating: 6, count: 64),
			firstUnuploadedPreKeyID: 7,
			requestedUploadCount: 2
		)

		await #expect(throws: SignalNativePreKeyUploadRequestError.invalidKeyMaterial) {
			try await adapter.uploadPreKeys(SignalPreKeyUploadRequest(
				currentCount: 1,
				requestedUploadCount: 2,
				nativeUploadRequest: request
			))
		}
		#expect(await backend.preKeyUploads.isEmpty)
	}

	@Test("rejects invalid native pre-key upload signed pre-key IDs before backend upload")
	func rejectsInvalidNativePreKeyUploadSignedPreKeyIDsBeforeBackendUpload() async throws {
		let backend = RecordingWhatsAppNativeSignalBackend(existingAddresses: [])
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: backend)
		let request = SignalNativePreKeyUploadRequest(
			registrationID: 1,
			identityPrivateKey: Data([0x01]),
			identityCurve25519PublicKey: Data(repeating: 2, count: 32),
			signedPreKeyID: 0x01_00_00_00,
			signedPreKeyPrivateKey: Data([0x04]),
			signedPreKeyCurve25519PublicKey: Data(repeating: 5, count: 32),
			signedPreKeySignature: Data(repeating: 6, count: 64),
			firstUnuploadedPreKeyID: 7,
			requestedUploadCount: 2
		)

		await #expect(throws: SignalNativePreKeyUploadRequestError.invalidKeyID) {
			try await adapter.uploadPreKeys(SignalPreKeyUploadRequest(
				currentCount: 1,
				requestedUploadCount: 2,
				nativeUploadRequest: request
			))
		}
		#expect(await backend.preKeyUploads.isEmpty)
	}

	@Test("rejects invalid native pre-key upload generated pre-key IDs before backend upload")
	func rejectsInvalidNativePreKeyUploadGeneratedPreKeyIDsBeforeBackendUpload() async throws {
		let backend = RecordingWhatsAppNativeSignalBackend(existingAddresses: [])
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: backend)
		let request = SignalNativePreKeyUploadRequest(
			registrationID: 1,
			identityPrivateKey: Data([0x01]),
			identityCurve25519PublicKey: Data(repeating: 2, count: 32),
			signedPreKeyID: 3,
			signedPreKeyPrivateKey: Data([0x04]),
			signedPreKeyCurve25519PublicKey: Data(repeating: 5, count: 32),
			signedPreKeySignature: Data(repeating: 6, count: 64),
			firstUnuploadedPreKeyID: -1,
			requestedUploadCount: 2
		)

		await #expect(throws: SignalNativePreKeyUploadRequestError.invalidKeyID) {
			try await adapter.uploadPreKeys(SignalPreKeyUploadRequest(
				currentCount: 1,
				requestedUploadCount: 2,
				nativeUploadRequest: request
			))
		}
		#expect(await backend.preKeyUploads.isEmpty)
	}

	@Test("rejects invalid native session install material before backend install")
	func rejectsInvalidNativeSessionInstallMaterialBeforeBackendInstall() async throws {
		let backend = RecordingWhatsAppNativeSignalBackend(existingAddresses: [])
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: backend)
		let request = SignalSessionNativeInstallRequest(
			jid: "123:1@s.whatsapp.net",
			address: SignalProtocolAddress(name: "123", deviceID: 1),
			registrationID: 7,
			identityCurve25519PublicKey: Data(repeating: 1, count: 32),
			signedPreKeyID: 8,
			signedPreKeyCurve25519PublicKey: Data(repeating: 2, count: 32),
			signedPreKeySignature: Data(repeating: 3, count: 63),
			preKeyID: 9,
			preKeyCurve25519PublicKey: Data(repeating: 4, count: 32)
		)

		await #expect(throws: SignalSessionBundleValidationError.invalidKeyMaterial) {
			try await adapter.installSession(request)
		}
		#expect(await backend.installedSessions.isEmpty)
	}

	@Test("rejects invalid native session install key IDs before backend install")
	func rejectsInvalidNativeSessionInstallKeyIDsBeforeBackendInstall() async throws {
		let backend = RecordingWhatsAppNativeSignalBackend(existingAddresses: [])
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: backend)
		let request = SignalSessionNativeInstallRequest(
			jid: "123:1@s.whatsapp.net",
			address: SignalProtocolAddress(name: "123", deviceID: 1),
			registrationID: 7,
			identityCurve25519PublicKey: Data(repeating: 1, count: 32),
			signedPreKeyID: 8,
			signedPreKeyCurve25519PublicKey: Data(repeating: 2, count: 32),
			signedPreKeySignature: Data(repeating: 3, count: 64),
			preKeyID: 0x01_00_00_00,
			preKeyCurve25519PublicKey: Data(repeating: 4, count: 32)
		)

		await #expect(throws: SignalSessionBundleValidationError.invalidKeyID) {
			try await adapter.installSession(request)
		}
		#expect(await backend.installedSessions.isEmpty)
	}

	@Test("rejects mismatched native session install addresses before backend install")
	func rejectsMismatchedNativeSessionInstallAddressesBeforeBackendInstall() async throws {
		let backend = RecordingWhatsAppNativeSignalBackend(existingAddresses: [])
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: backend)

		await #expect(throws: SignalSessionBundleValidationError.invalidAddress) {
			try await adapter.installSession(validSessionInstallRequest(
				jid: "123:1@s.whatsapp.net",
				address: SignalProtocolAddress(name: "999", deviceID: 1)
			))
		}
		await #expect(throws: SignalSessionBundleValidationError.invalidAddress) {
			try await adapter.installSession(validSessionInstallRequest(
				localJID: "999:0@s.whatsapp.net",
				localAddress: SignalProtocolAddress(name: "123", deviceID: 0)
			))
		}
		#expect(await backend.installedSessions.isEmpty)
	}

	@Test("rejects empty native direct ciphertext before returning encrypted message")
	func rejectsEmptyNativeDirectCiphertextBeforeReturningEncryptedMessage() async throws {
		let backend = RecordingWhatsAppNativeSignalBackend(
			existingAddresses: [],
			directCiphertext: Data()
		)
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: backend)

		await #expect(throws: WhatsAppNativeSignalBackendAdapterError.emptyDirectCiphertext) {
			_ = try await adapter.encryptMessage(SignalDirectMessageEncryptionRequest(
				jid: "123:1@s.whatsapp.net",
				data: Data([0x01])
			))
		}
	}

	@Test("rejects empty native group ciphertext before returning encrypted message")
	func rejectsEmptyNativeGroupCiphertextBeforeReturningEncryptedMessage() async throws {
		let backend = RecordingWhatsAppNativeSignalBackend(
			existingAddresses: [],
			groupCiphertext: Data()
		)
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: backend)

		await #expect(throws: WhatsAppNativeSignalBackendAdapterError.emptyGroupCiphertext) {
			_ = try await adapter.encryptGroupMessage(SignalGroupMessageEncryptionRequest(
				groupJID: "111-222@g.us",
				senderJID: "123@s.whatsapp.net",
				data: Data([0x01])
			))
		}
	}

	@Test("rejects empty native sender key distribution before returning encrypted group message")
	func rejectsEmptyNativeSenderKeyDistributionBeforeReturningEncryptedGroupMessage() async throws {
		let backend = RecordingWhatsAppNativeSignalBackend(
			existingAddresses: [],
			senderKeyDistributionMessage: Data()
		)
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: backend)

		await #expect(throws: WhatsAppNativeSignalBackendAdapterError.emptySenderKeyDistributionMessage) {
			_ = try await adapter.encryptGroupMessage(SignalGroupMessageEncryptionRequest(
				groupJID: "111-222@g.us",
				senderJID: "123@s.whatsapp.net",
				data: Data([0x01])
			))
		}
	}

	@Test("rejects empty native plaintext before returning decrypted messages")
	func rejectsEmptyNativePlaintextBeforeReturningDecryptedMessages() async throws {
		let adapter = WhatsAppNativeSignalBackendAdapter(backend: RecordingWhatsAppNativeSignalBackend(
			existingAddresses: [],
			directPlaintext: Data(),
			groupPlaintext: Data()
		))

		await #expect(throws: WhatsAppNativeSignalBackendAdapterError.emptyDirectPlaintext) {
			_ = try await adapter.decryptMessage(SignalDirectMessageDecryptionRequest(
				jid: "123:1@s.whatsapp.net",
				ciphertextType: .signalMessage,
				ciphertext: Data([0x01])
			))
		}
		await #expect(throws: WhatsAppNativeSignalBackendAdapterError.emptyGroupPlaintext) {
			_ = try await adapter.decryptGroupMessage(SignalGroupMessageDecryptionRequest(
				groupJID: "111-222@g.us",
				authorJID: "123:1@s.whatsapp.net",
				ciphertext: Data([0x02])
			))
		}
	}
}

private actor RecordingWhatsAppNativeSignalBackend: WhatsAppNativeSignalBackend {
	let existingAddresses: Set<SignalProtocolAddress>
	let signedPreKeySignature: Data
	let directCiphertext: Data?
	let groupCiphertext: Data?
	let senderKeyDistributionMessage: Data?
	let directPlaintext: Data?
	let groupPlaintext: Data?
	private(set) var readinessCheckCount = 0
	var importedAccounts: [WhatsAppNativeSignalAccount] = []
	var accountChecks: [WhatsAppNativeSignalAccount] = []
	var sessionChecks: [[SignalSessionAddressCheck]] = []
	var installedSessions: [WhatsAppNativeSignalSession] = []
	var directMessages: [WhatsAppNativeDirectMessage] = []
	var groupMessages: [WhatsAppNativeGroupMessage] = []
	var directCiphertextMessages: [WhatsAppNativeDirectCiphertextMessage] = []
	var groupCiphertextMessages: [WhatsAppNativeGroupCiphertextMessage] = []
	var senderKeyMessages: [WhatsAppNativeSenderKeyDistributionMessage] = []
	var preKeyUploads: [SignalNativePreKeyUploadRequest] = []

	init(
		existingAddresses: Set<SignalProtocolAddress>,
		signedPreKeySignature: Data = Data(repeating: 0x51, count: 64),
		directCiphertext: Data? = nil,
		groupCiphertext: Data? = nil,
		senderKeyDistributionMessage: Data? = nil,
		directPlaintext: Data? = nil,
		groupPlaintext: Data? = nil
	) {
		self.existingAddresses = existingAddresses
		self.signedPreKeySignature = signedPreKeySignature
		self.directCiphertext = directCiphertext
		self.groupCiphertext = groupCiphertext
		self.senderKeyDistributionMessage = senderKeyDistributionMessage
		self.directPlaintext = directPlaintext
		self.groupPlaintext = groupPlaintext
	}

	nonisolated func signSignedPreKey(identityPrivateKey: Data, signedPreKeyPublicKey: Data) throws -> Data {
		signedPreKeySignature
	}

	func assertReadyForSignalOperations() async throws {
		readinessCheckCount += 1
	}

	func importAccount(_ account: WhatsAppNativeSignalAccount) async throws {
		importedAccounts.append(account)
	}

	func containsAccount(_ account: WhatsAppNativeSignalAccount) async throws -> Bool {
		accountChecks.append(account)
		return account.address == SignalProtocolAddress(name: "999", deviceID: 0)
	}

	func existingSessions(for checks: [SignalSessionAddressCheck]) async throws -> Set<SignalProtocolAddress> {
		sessionChecks.append(checks)
		return Set(checks.map(\.address).filter(existingAddresses.contains))
	}

	func installSession(_ session: WhatsAppNativeSignalSession) async throws {
		installedSessions.append(session)
	}

	func encryptDirectMessage(_ message: WhatsAppNativeDirectMessage) async throws -> WhatsAppNativeDirectCiphertext {
		directMessages.append(message)
		return WhatsAppNativeDirectCiphertext(
			type: .signalMessage,
			ciphertext: directCiphertext ?? message.plaintext + Data([0x01])
		)
	}

	func encryptGroupMessage(_ message: WhatsAppNativeGroupMessage) async throws -> WhatsAppNativeGroupCiphertext {
		groupMessages.append(message)
		return WhatsAppNativeGroupCiphertext(
			ciphertext: groupCiphertext ?? message.plaintext + Data([0x02]),
			senderKeyDistributionMessage: senderKeyDistributionMessage ?? Data([0x21])
		)
	}

	func decryptDirectMessage(_ message: WhatsAppNativeDirectCiphertextMessage) async throws -> Data {
		directCiphertextMessages.append(message)
		return directPlaintext ?? message.ciphertext + Data([0x03])
	}

	func decryptGroupMessage(_ message: WhatsAppNativeGroupCiphertextMessage) async throws -> Data {
		groupCiphertextMessages.append(message)
		return groupPlaintext ?? message.ciphertext + Data([0x04])
	}

	func processSenderKeyDistributionMessage(_ message: WhatsAppNativeSenderKeyDistributionMessage) async throws {
		senderKeyMessages.append(message)
	}

	func uploadPreKeys(_ request: SignalNativePreKeyUploadRequest) async throws {
		preKeyUploads.append(request)
	}
}

private func validSessionInstallRequest(
	jid: String = "123:1@s.whatsapp.net",
	address: SignalProtocolAddress = SignalProtocolAddress(name: "123", deviceID: 1),
	localJID: String? = nil,
	localAddress: SignalProtocolAddress? = nil
) -> SignalSessionNativeInstallRequest {
	SignalSessionNativeInstallRequest(
		jid: jid,
		address: address,
		localJID: localJID,
		localAddress: localAddress,
		registrationID: 7,
		identityCurve25519PublicKey: Data(repeating: 1, count: 32),
		signedPreKeyID: 8,
		signedPreKeyCurve25519PublicKey: Data(repeating: 2, count: 32),
		signedPreKeySignature: Data(repeating: 3, count: 64),
		preKeyID: 9,
		preKeyCurve25519PublicKey: Data(repeating: 4, count: 32)
	)
}
