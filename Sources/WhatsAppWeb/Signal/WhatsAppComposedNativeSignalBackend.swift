import Foundation

public protocol WhatsAppNativeSignalStore: Sendable {
	func assertReadyForNativeSignalStorage() async throws
	func importAccount(_ account: WhatsAppNativeSignalAccount) async throws
	func containsAccount(_ account: WhatsAppNativeSignalAccount) async throws -> Bool
	func existingSessions(for checks: [SignalSessionAddressCheck]) async throws -> Set<SignalProtocolAddress>
	func installSession(_ session: WhatsAppNativeSignalSession) async throws
	func uploadPreKeys(_ request: SignalNativePreKeyUploadRequest) async throws
}

public protocol WhatsAppNativeSignalCryptoProvider: SignalNativeOperationReadinessChecking {
	func signSignedPreKey(identityPrivateKey: Data, signedPreKeyPublicKey: Data) throws -> Data
	func encryptDirectMessage(_ message: WhatsAppNativeDirectMessage) async throws -> WhatsAppNativeDirectCiphertext
	func encryptGroupMessage(_ message: WhatsAppNativeGroupMessage) async throws -> WhatsAppNativeGroupCiphertext
	func decryptDirectMessage(_ message: WhatsAppNativeDirectCiphertextMessage) async throws -> Data
	func decryptGroupMessage(_ message: WhatsAppNativeGroupCiphertextMessage) async throws -> Data
	func processSenderKeyDistributionMessage(_ message: WhatsAppNativeSenderKeyDistributionMessage) async throws
}

public final class WhatsAppComposedNativeSignalBackend: WhatsAppNativeSignalBackend, @unchecked Sendable {
	private let store: any WhatsAppNativeSignalStore
	private let cryptoProvider: any WhatsAppNativeSignalCryptoProvider

	public init(store: any WhatsAppNativeSignalStore, cryptoProvider: any WhatsAppNativeSignalCryptoProvider) {
		self.store = store
		self.cryptoProvider = cryptoProvider
	}

	public func signSignedPreKey(identityPrivateKey: Data, signedPreKeyPublicKey: Data) throws -> Data {
		try cryptoProvider.signSignedPreKey(
			identityPrivateKey: identityPrivateKey,
			signedPreKeyPublicKey: signedPreKeyPublicKey
		)
	}

	public func assertReadyForSignalOperations() async throws {
		try await store.assertReadyForNativeSignalStorage()
		try await cryptoProvider.assertReadyForSignalOperations()
	}

	public func importAccount(_ account: WhatsAppNativeSignalAccount) async throws {
		try await store.importAccount(account)
	}

	public func containsAccount(_ account: WhatsAppNativeSignalAccount) async throws -> Bool {
		try await store.containsAccount(account)
	}

	public func existingSessions(for checks: [SignalSessionAddressCheck]) async throws -> Set<SignalProtocolAddress> {
		try await store.existingSessions(for: checks)
	}

	public func installSession(_ session: WhatsAppNativeSignalSession) async throws {
		try await store.installSession(session)
	}

	public func encryptDirectMessage(_ message: WhatsAppNativeDirectMessage) async throws -> WhatsAppNativeDirectCiphertext {
		try await cryptoProvider.encryptDirectMessage(message)
	}

	public func encryptGroupMessage(_ message: WhatsAppNativeGroupMessage) async throws -> WhatsAppNativeGroupCiphertext {
		try await cryptoProvider.encryptGroupMessage(message)
	}

	public func decryptDirectMessage(_ message: WhatsAppNativeDirectCiphertextMessage) async throws -> Data {
		try await cryptoProvider.decryptDirectMessage(message)
	}

	public func decryptGroupMessage(_ message: WhatsAppNativeGroupCiphertextMessage) async throws -> Data {
		try await cryptoProvider.decryptGroupMessage(message)
	}

	public func processSenderKeyDistributionMessage(_ message: WhatsAppNativeSenderKeyDistributionMessage) async throws {
		try await cryptoProvider.processSenderKeyDistributionMessage(message)
	}

	public func uploadPreKeys(_ request: SignalNativePreKeyUploadRequest) async throws {
		try await store.uploadPreKeys(request)
	}
}
