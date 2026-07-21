import Foundation

public protocol WhatsAppNativeSignalBackend: SignalNativeOperationReadinessChecking {
	func signSignedPreKey(identityPrivateKey: Data, signedPreKeyPublicKey: Data) throws -> Data
	func importAccount(_ account: WhatsAppNativeSignalAccount) async throws
	func containsAccount(_ account: WhatsAppNativeSignalAccount) async throws -> Bool
	func existingSessions(for checks: [SignalSessionAddressCheck]) async throws -> Set<SignalProtocolAddress>
	func installSession(_ session: WhatsAppNativeSignalSession) async throws
	func encryptDirectMessage(_ message: WhatsAppNativeDirectMessage) async throws -> WhatsAppNativeDirectCiphertext
	func encryptGroupMessage(_ message: WhatsAppNativeGroupMessage) async throws -> WhatsAppNativeGroupCiphertext
	func decryptDirectMessage(_ message: WhatsAppNativeDirectCiphertextMessage) async throws -> Data
	func decryptGroupMessage(_ message: WhatsAppNativeGroupCiphertextMessage) async throws -> Data
	func processSenderKeyDistributionMessage(_ message: WhatsAppNativeSenderKeyDistributionMessage) async throws
	func uploadPreKeys(_ request: SignalNativePreKeyUploadRequest) async throws
}

public final class WhatsAppNativeSignalBackendAdapter: WhatsAppNativeSignalAdapter, @unchecked Sendable {
	private let backend: any WhatsAppNativeSignalBackend

	public init(backend: any WhatsAppNativeSignalBackend) {
		self.backend = backend
	}

	public convenience init(
		store: any WhatsAppNativeSignalStore,
		cryptoProvider: any WhatsAppNativeSignalCryptoProvider
	) {
		self.init(backend: WhatsAppComposedNativeSignalBackend(
			store: store,
			cryptoProvider: cryptoProvider
		))
	}

	public func signSignedPreKey(_ request: SignalSignedPreKeySignatureRequest) throws -> Data {
		let signature = try backend.signSignedPreKey(
			identityPrivateKey: request.identityPrivateKey,
			signedPreKeyPublicKey: request.signedPreKeyPublicKey
		)
		guard signature.count == 64 else {
			throw WhatsAppNativeSignalBackendAdapterError.invalidSignedPreKeySignature
		}
		return signature
	}

	public func assertReadyForSignalOperations() async throws {
		try await backend.assertReadyForSignalOperations()
	}

	public func assertReadyForCredentialSigning() throws {
		try (self as any SignalSignedPreKeySigning).assertReadyForCredentialSigning()
	}

	public func importAccount(_ request: SignalNativeAccountImportRequest) async throws {
		try request.validate()
		try await backend.importAccount(WhatsAppNativeSignalAccount(request: request))
	}

	public func containsAccount(_ request: SignalNativeAccountImportRequest) async throws -> Bool {
		try request.validate()
		return try await backend.containsAccount(WhatsAppNativeSignalAccount(request: request))
	}

	public func existingSessions(for checks: [SignalSessionAddressCheck]) async throws -> Set<SignalProtocolAddress> {
		try await backend.existingSessions(for: checks)
	}

	public func installSession(_ request: SignalSessionNativeInstallRequest) async throws {
		try request.validate()
		try await backend.installSession(WhatsAppNativeSignalSession(request: request))
	}

	public func encryptMessage(_ request: SignalDirectMessageEncryptionRequest) async throws -> EncryptedMessage {
		let encrypted = try await backend.encryptDirectMessage(WhatsAppNativeDirectMessage(request: request))
		guard !encrypted.ciphertext.isEmpty else {
			throw WhatsAppNativeSignalBackendAdapterError.emptyDirectCiphertext
		}
		return EncryptedMessage(ciphertextType: encrypted.type, ciphertext: encrypted.ciphertext)
	}

	public func encryptGroupMessage(_ request: SignalGroupMessageEncryptionRequest) async throws -> EncryptedGroupMessage {
		let encrypted = try await backend.encryptGroupMessage(WhatsAppNativeGroupMessage(request: request))
		guard !encrypted.ciphertext.isEmpty else {
			throw WhatsAppNativeSignalBackendAdapterError.emptyGroupCiphertext
		}
		guard !encrypted.senderKeyDistributionMessage.isEmpty else {
			throw WhatsAppNativeSignalBackendAdapterError.emptySenderKeyDistributionMessage
		}
		return EncryptedGroupMessage(
			ciphertext: encrypted.ciphertext,
			senderKeyDistributionMessage: encrypted.senderKeyDistributionMessage
		)
	}

	public func decryptMessage(_ request: SignalDirectMessageDecryptionRequest) async throws -> Data {
		let plaintext = try await backend.decryptDirectMessage(WhatsAppNativeDirectCiphertextMessage(request: request))
		guard !plaintext.isEmpty else {
			throw WhatsAppNativeSignalBackendAdapterError.emptyDirectPlaintext
		}
		return plaintext
	}

	public func decryptGroupMessage(_ request: SignalGroupMessageDecryptionRequest) async throws -> Data {
		let plaintext = try await backend.decryptGroupMessage(WhatsAppNativeGroupCiphertextMessage(request: request))
		guard !plaintext.isEmpty else {
			throw WhatsAppNativeSignalBackendAdapterError.emptyGroupPlaintext
		}
		return plaintext
	}

	public func processSenderKeyDistributionMessage(_ request: SenderKeyDistributionMessageRequest) async throws {
		try await backend.processSenderKeyDistributionMessage(WhatsAppNativeSenderKeyDistributionMessage(request: request))
	}

	public func uploadPreKeys(_ request: SignalPreKeyUploadRequest) async throws {
		guard let nativeUploadRequest = request.nativeUploadRequest else {
			throw WhatsAppNativeSignalBackendAdapterError.missingNativePreKeyUploadRequest
		}
		try nativeUploadRequest.validate()
		try await backend.uploadPreKeys(nativeUploadRequest)
	}
}

public enum WhatsAppNativeSignalBackendAdapterError: Error, Equatable, Sendable {
	case missingNativePreKeyUploadRequest
	case invalidSignedPreKeySignature
	case emptyDirectCiphertext
	case emptyGroupCiphertext
	case emptySenderKeyDistributionMessage
	case emptyDirectPlaintext
	case emptyGroupPlaintext
}

public struct WhatsAppNativeSignalAccount: Sendable {
	public let localJID: String
	public let address: SignalProtocolAddress
	public let keyMaterial: SignalNativeAccountKeyMaterial

	public init(request: SignalNativeAccountImportRequest) {
		localJID = request.localJID
		address = request.localAddress
		keyMaterial = request.keyMaterial
	}
}

public struct WhatsAppNativeSignalSession: Sendable {
	public let request: SignalSessionNativeInstallRequest
	public let jid: String
	public let address: SignalProtocolAddress
	public let localJID: String?
	public let localAddress: SignalProtocolAddress?
	public let registrationID: Int
	public let identityCurve25519PublicKey: Data
	public let signedPreKeyID: Int
	public let signedPreKeyCurve25519PublicKey: Data
	public let signedPreKeySignature: Data
	public let preKeyID: Int
	public let preKeyCurve25519PublicKey: Data

	public init(request: SignalSessionNativeInstallRequest) {
		self.request = request
		jid = request.jid
		address = request.address
		localJID = request.localJID
		localAddress = request.localAddress
		registrationID = request.registrationID
		identityCurve25519PublicKey = request.identityCurve25519PublicKey
		signedPreKeyID = request.signedPreKeyID
		signedPreKeyCurve25519PublicKey = request.signedPreKeyCurve25519PublicKey
		signedPreKeySignature = request.signedPreKeySignature
		preKeyID = request.preKeyID
		preKeyCurve25519PublicKey = request.preKeyCurve25519PublicKey
	}
}

public struct WhatsAppNativeDirectMessage: Sendable {
	public let jid: String
	public let localJID: String?
	public let remoteAddress: SignalProtocolAddress
	public let localAddress: SignalProtocolAddress?
	public let plaintext: Data

	public init(request: SignalDirectMessageEncryptionRequest) {
		jid = request.jid
		localJID = request.localJID
		remoteAddress = request.address
		localAddress = request.localAddress
		plaintext = request.data
	}
}

public struct WhatsAppNativeGroupMessage: Sendable {
	public let groupJID: String
	public let senderJID: String
	public let senderAddress: SignalProtocolAddress
	public let plaintext: Data

	public init(request: SignalGroupMessageEncryptionRequest) {
		groupJID = request.groupJID
		senderJID = request.senderJID
		senderAddress = request.senderAddress
		plaintext = request.data
	}
}

public struct WhatsAppNativeDirectCiphertext: Sendable {
	public let type: SignalDirectCiphertextType
	public let ciphertext: Data

	public init(type: SignalDirectCiphertextType, ciphertext: Data) {
		self.type = type
		self.ciphertext = ciphertext
	}
}

public struct WhatsAppNativeGroupCiphertext: Sendable {
	public let ciphertext: Data
	public let senderKeyDistributionMessage: Data

	public init(ciphertext: Data, senderKeyDistributionMessage: Data) {
		self.ciphertext = ciphertext
		self.senderKeyDistributionMessage = senderKeyDistributionMessage
	}
}

public struct WhatsAppNativeDirectCiphertextMessage: Sendable {
	public let jid: String
	public let localJID: String?
	public let remoteAddress: SignalProtocolAddress
	public let localAddress: SignalProtocolAddress?
	public let ciphertextType: SignalDirectCiphertextType
	public let type: SignalDirectCiphertextType
	public let ciphertext: Data

	public init(request: SignalDirectMessageDecryptionRequest) {
		jid = request.jid
		localJID = request.localJID
		remoteAddress = request.address
		localAddress = request.localAddress
		ciphertextType = request.ciphertextType
		type = request.ciphertextType
		ciphertext = request.ciphertext
	}
}

public struct WhatsAppNativeGroupCiphertextMessage: Sendable {
	public let groupJID: String
	public let authorJID: String
	public let authorAddress: SignalProtocolAddress
	public let ciphertext: Data

	public init(request: SignalGroupMessageDecryptionRequest) {
		groupJID = request.groupJID
		authorJID = request.authorJID
		authorAddress = request.authorAddress
		ciphertext = request.ciphertext
	}
}

public struct WhatsAppNativeSenderKeyDistributionMessage: Sendable {
	public let authorJID: String
	public let groupJID: String?
	public let authorAddress: SignalProtocolAddress
	public let senderKeyDistributionData: Data?
	public let messageData: Data

	public init(request: SenderKeyDistributionMessageRequest) {
		authorJID = request.authorJID
		groupJID = request.groupJID
		authorAddress = request.authorAddress
		senderKeyDistributionData = request.senderKeyDistributionData
		messageData = request.messageData
	}
}
