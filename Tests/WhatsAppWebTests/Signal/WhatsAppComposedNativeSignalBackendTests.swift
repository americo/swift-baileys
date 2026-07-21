import Foundation
import Testing
import WhatsAppWeb

@Suite("WhatsApp composed native Signal backend")
struct WhatsAppComposedNativeSignalBackendTests {
	@Test("delegates storage and crypto responsibilities separately")
	func delegatesStorageAndCryptoResponsibilitiesSeparately() async throws {
		let store = RecordingComposedNativeSignalStore(existingAddresses: [
			SignalProtocolAddress(name: "123", deviceID: 1)
		])
		let crypto = RecordingComposedNativeSignalCryptoProvider()
		let backend = WhatsAppComposedNativeSignalBackend(store: store, cryptoProvider: crypto)
		let account = WhatsAppNativeSignalAccount(request: SignalNativeAccountImportRequest(
			localJID: "999:0@s.whatsapp.net",
			localAddress: SignalProtocolAddress(name: "999", deviceID: 0),
			keyMaterial: SignalNativeAccountKeyMaterial(
				registrationID: 1,
				identityPrivateKey: Data(repeating: 0x01, count: 32),
				identityCurve25519PublicKey: Data(repeating: 0x02, count: 32),
				signedPreKeyID: 2,
				signedPreKeyPrivateKey: Data(repeating: 0x03, count: 32),
				signedPreKeyCurve25519PublicKey: Data(repeating: 0x04, count: 32),
				signedPreKeySignature: Data(repeating: 0x05, count: 64)
			)
		))
		let session = WhatsAppNativeSignalSession(request: SignalSessionNativeInstallRequest(
			jid: "123:1@s.whatsapp.net",
			address: SignalProtocolAddress(name: "123", deviceID: 1),
			localJID: account.localJID,
			localAddress: account.address,
			registrationID: 7,
			identityCurve25519PublicKey: Data(repeating: 0x06, count: 32),
			signedPreKeyID: 8,
			signedPreKeyCurve25519PublicKey: Data(repeating: 0x07, count: 32),
			signedPreKeySignature: Data(repeating: 0x08, count: 64),
			preKeyID: 9,
			preKeyCurve25519PublicKey: Data(repeating: 0x09, count: 32)
		))
		let upload = SignalNativePreKeyUploadRequest(
			localJID: account.localJID,
			localAddress: account.address,
			currentServerPreKeyCount: 1,
			registrationID: account.keyMaterial.registrationID,
			identityPrivateKey: account.keyMaterial.identityPrivateKey,
			identityCurve25519PublicKey: account.keyMaterial.identityCurve25519PublicKey,
			signedPreKeyID: account.keyMaterial.signedPreKeyID,
			signedPreKeyPrivateKey: account.keyMaterial.signedPreKeyPrivateKey,
			signedPreKeyCurve25519PublicKey: account.keyMaterial.signedPreKeyCurve25519PublicKey,
			signedPreKeySignature: account.keyMaterial.signedPreKeySignature,
			firstUnuploadedPreKeyID: 10,
			requestedUploadCount: 2
		)

		let signature = try backend.signSignedPreKey(
			identityPrivateKey: Data([0x11]),
			signedPreKeyPublicKey: Data([0x12])
		)
		try await backend.assertReadyForSignalOperations()
		try await backend.importAccount(account)
		let containsAccount = try await backend.containsAccount(account)
		let existingSessions = try await backend.existingSessions(for: [
			SignalSessionAddressCheck(jid: session.jid, address: session.address),
			SignalSessionAddressCheck(jid: "456:1@s.whatsapp.net", address: SignalProtocolAddress(name: "456", deviceID: 1))
		])
		try await backend.installSession(session)
		let direct = try await backend.encryptDirectMessage(WhatsAppNativeDirectMessage(
			request: try SignalDirectMessageEncryptionRequest(jid: session.jid, data: Data([0x21]))
		))
		let group = try await backend.encryptGroupMessage(WhatsAppNativeGroupMessage(
			request: try SignalGroupMessageEncryptionRequest(
				groupJID: "111-222@g.us",
				senderJID: account.localJID,
				data: Data([0x22])
			)
		))
		let directPlaintext = try await backend.decryptDirectMessage(WhatsAppNativeDirectCiphertextMessage(
			request: try SignalDirectMessageDecryptionRequest(
				jid: session.jid,
				ciphertextType: .signalMessage,
				ciphertext: Data([0x23])
			)
		))
		let groupPlaintext = try await backend.decryptGroupMessage(WhatsAppNativeGroupCiphertextMessage(
			request: try SignalGroupMessageDecryptionRequest(
				groupJID: "111-222@g.us",
				authorJID: session.jid,
				ciphertext: Data([0x24])
			)
		))
		try await backend.processSenderKeyDistributionMessage(WhatsAppNativeSenderKeyDistributionMessage(
			request: try SenderKeyDistributionMessageRequest(authorJID: session.jid, messageData: Data([0x25]))
		))
		try await backend.uploadPreKeys(upload)

		#expect(signature == Data(repeating: 0x51, count: 64))
		#expect(containsAccount)
		#expect(existingSessions == [session.address])
		#expect(direct.ciphertext == Data([0x21, 0x31]))
		#expect(group.senderKeyDistributionMessage == Data([0x32]))
		#expect(directPlaintext == Data([0x23, 0x33]))
		#expect(groupPlaintext == Data([0x24, 0x34]))
		#expect(await store.readinessCheckCount == 1)
		#expect(await store.importedAccounts.map(\.address) == [account.address])
		#expect(await store.installedSessions.map(\.address) == [session.address])
		#expect(await store.preKeyUploads == [upload])
		#expect(await crypto.readinessCheckCount == 1)
		#expect(await crypto.directMessages.map(\.plaintext) == [Data([0x21])])
		#expect(await crypto.senderKeyMessages.map(\.messageData) == [Data([0x25])])
	}

	@Test("native Signal adapter composes store and crypto provider directly")
	func nativeSignalAdapterComposesStoreAndCryptoProviderDirectly() async throws {
		let store = RecordingComposedNativeSignalStore(existingAddresses: [
			SignalProtocolAddress(name: "123", deviceID: 1)
		])
		let crypto = RecordingComposedNativeSignalCryptoProvider()
		let adapter = WhatsAppNativeSignalBackendAdapter(store: store, cryptoProvider: crypto)

		try await adapter.assertReadyForSignalOperations()
		let encrypted = try await adapter.encryptMessage(SignalDirectMessageEncryptionRequest(
			jid: "123:1@s.whatsapp.net",
			data: Data([0x41])
		))

		#expect(encrypted == EncryptedMessage(ciphertextType: .signalMessage, ciphertext: Data([0x41, 0x31])))
		#expect(await store.readinessCheckCount == 1)
		#expect(await crypto.readinessCheckCount == 1)
	}
}

private actor RecordingComposedNativeSignalStore: WhatsAppNativeSignalStore {
	let existingAddresses: Set<SignalProtocolAddress>
	private(set) var readinessCheckCount = 0
	private(set) var importedAccounts: [WhatsAppNativeSignalAccount] = []
	private(set) var accountChecks: [WhatsAppNativeSignalAccount] = []
	private(set) var installedSessions: [WhatsAppNativeSignalSession] = []
	private(set) var preKeyUploads: [SignalNativePreKeyUploadRequest] = []

	init(existingAddresses: Set<SignalProtocolAddress>) {
		self.existingAddresses = existingAddresses
	}

	func assertReadyForNativeSignalStorage() async throws {
		readinessCheckCount += 1
	}

	func importAccount(_ account: WhatsAppNativeSignalAccount) async throws {
		importedAccounts.append(account)
	}

	func containsAccount(_ account: WhatsAppNativeSignalAccount) async throws -> Bool {
		accountChecks.append(account)
		return true
	}

	func existingSessions(for checks: [SignalSessionAddressCheck]) async throws -> Set<SignalProtocolAddress> {
		Set(checks.map(\.address).filter(existingAddresses.contains))
	}

	func installSession(_ session: WhatsAppNativeSignalSession) async throws {
		installedSessions.append(session)
	}

	func uploadPreKeys(_ request: SignalNativePreKeyUploadRequest) async throws {
		preKeyUploads.append(request)
	}
}

private actor RecordingComposedNativeSignalCryptoProvider: WhatsAppNativeSignalCryptoProvider {
	private(set) var readinessCheckCount = 0
	private(set) var directMessages: [WhatsAppNativeDirectMessage] = []
	private(set) var senderKeyMessages: [WhatsAppNativeSenderKeyDistributionMessage] = []

	nonisolated func signSignedPreKey(identityPrivateKey: Data, signedPreKeyPublicKey: Data) throws -> Data {
		Data(repeating: 0x51, count: 64)
	}

	func assertReadyForSignalOperations() async throws {
		readinessCheckCount += 1
	}

	func encryptDirectMessage(_ message: WhatsAppNativeDirectMessage) async throws -> WhatsAppNativeDirectCiphertext {
		directMessages.append(message)
		return WhatsAppNativeDirectCiphertext(type: .signalMessage, ciphertext: message.plaintext + Data([0x31]))
	}

	func encryptGroupMessage(_ message: WhatsAppNativeGroupMessage) async throws -> WhatsAppNativeGroupCiphertext {
		WhatsAppNativeGroupCiphertext(
			ciphertext: message.plaintext + Data([0x31]),
			senderKeyDistributionMessage: Data([0x32])
		)
	}

	func decryptDirectMessage(_ message: WhatsAppNativeDirectCiphertextMessage) async throws -> Data {
		message.ciphertext + Data([0x33])
	}

	func decryptGroupMessage(_ message: WhatsAppNativeGroupCiphertextMessage) async throws -> Data {
		message.ciphertext + Data([0x34])
	}

	func processSenderKeyDistributionMessage(_ message: WhatsAppNativeSenderKeyDistributionMessage) async throws {
		senderKeyMessages.append(message)
	}
}
