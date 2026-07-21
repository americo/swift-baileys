import Foundation
import WhatsAppWeb

enum NativeSignalBridgeExample {
	static func makeRuntime(
		authDirectory: URL,
		store: any NativeSignalStore,
		cryptoProvider: any NativeSignalCryptoProvider,
		ensureReadyForMessagingOnLoad: Bool = false
	) async throws -> NativeSignalRuntime {
		try await WhatsAppNativeSignalRuntime.make(
			authDirectory: authDirectory,
			store: store,
			cryptoProvider: cryptoProvider,
			ensureReadyForMessagingOnLoad: ensureReadyForMessagingOnLoad
		)
	}

	static func makeRuntime(
		authDirectory: URL,
		backend: any NativeSignalBackend,
		ensureReadyForMessagingOnLoad: Bool = false
	) async throws -> NativeSignalRuntime {
		try await WhatsAppNativeSignalRuntime.make(
			authDirectory: authDirectory,
			backend: backend,
			ensureReadyForMessagingOnLoad: ensureReadyForMessagingOnLoad
		)
	}

	static func makeClient(
		authDirectory: URL,
		store: any NativeSignalStore,
		cryptoProvider: any NativeSignalCryptoProvider,
		ensureReadyForMessagingOnLoad: Bool = false
	) async throws -> WhatsAppClient {
		try await makeRuntime(
			authDirectory: authDirectory,
			store: store,
			cryptoProvider: cryptoProvider,
			ensureReadyForMessagingOnLoad: ensureReadyForMessagingOnLoad
		).client
	}

	static func makeClient(
		authDirectory: URL,
		backend: any NativeSignalBackend,
		ensureReadyForMessagingOnLoad: Bool = false
	) async throws -> WhatsAppClient {
		try await makeRuntime(
			authDirectory: authDirectory,
			backend: backend,
			ensureReadyForMessagingOnLoad: ensureReadyForMessagingOnLoad
		).client
	}

	static func runReadinessMonitor(runtime: NativeSignalRuntime) async throws {
		try await runtime.runReadinessMonitor()
	}

	static func startReadinessMonitor(runtime: NativeSignalRuntime) -> Task<Void, any Error> {
		runtime.startReadinessMonitor()
	}

	static func makeBackendSkeleton() -> any NativeSignalBackend {
		WhatsAppComposedNativeSignalBackend(
			store: ExampleNativeSignalStore(),
			cryptoProvider: MissingExampleNativeSignalCryptoProvider()
		)
	}

	static func runSelfTest() async throws {
		let store = ExampleNativeSignalStore()
		let backend = WhatsAppComposedNativeSignalBackend(
			store: store,
			cryptoProvider: MissingExampleNativeSignalCryptoProvider()
		)
		let account = NativeSignalAccount(request: SignalNativeAccountImportRequest(
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
		let session = NativeSignalSession(request: SignalSessionNativeInstallRequest(
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
		let upload = NativePreKeyUploadRequest(
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

		try await backend.importAccount(account)
		guard try await backend.containsAccount(account) else {
			throw ExampleNativeSignalBackendError.selfTestFailed
		}
		try await backend.installSession(session)
		let existingSessions = try await backend.existingSessions(for: [
			SignalSessionAddressCheck(jid: session.jid, address: session.address)
		])
		guard existingSessions == [session.address] else {
			throw ExampleNativeSignalBackendError.selfTestFailed
		}
		try await backend.uploadPreKeys(upload)
		guard await store.uploadedPreKeyRequestsCount == 1 else {
			throw ExampleNativeSignalBackendError.selfTestFailed
		}

		let crypto = RecordingExampleNativeSignalCryptoProvider()
		let cryptoBackend = WhatsAppComposedNativeSignalBackend(
			store: ExampleNativeSignalStore(),
			cryptoProvider: crypto
		)
		let signature = try cryptoBackend.signSignedPreKey(
			identityPrivateKey: Data(repeating: 0x0a, count: 32),
			signedPreKeyPublicKey: Data(repeating: 0x0b, count: 32)
		)
		let directCiphertext = try await cryptoBackend.encryptDirectMessage(NativeDirectMessage(
			request: try SignalDirectMessageEncryptionRequest(jid: session.jid, data: Data([0x0c]))
		))
		let groupCiphertext = try await cryptoBackend.encryptGroupMessage(NativeGroupMessage(
			request: try SignalGroupMessageEncryptionRequest(
				groupJID: "111-222@g.us",
				senderJID: account.localJID,
				data: Data([0x0d])
			)
		))
		let directPlaintext = try await cryptoBackend.decryptDirectMessage(NativeDirectCiphertextMessage(
			request: try SignalDirectMessageDecryptionRequest(
				jid: session.jid,
				ciphertextType: .signalMessage,
				ciphertext: Data([0x0e])
			)
		))
		let groupPlaintext = try await cryptoBackend.decryptGroupMessage(NativeGroupCiphertextMessage(
			request: try SignalGroupMessageDecryptionRequest(
				groupJID: "111-222@g.us",
				authorJID: session.jid,
				ciphertext: Data([0x0f])
			)
		))
		try await cryptoBackend.processSenderKeyDistributionMessage(NativeSenderKeyDistributionMessage(
			request: try SenderKeyDistributionMessageRequest(
				authorJID: session.jid,
				groupJID: "111-222@g.us",
				senderKeyDistributionData: Data([0x10]),
				messageData: Data([0x11])
			)
		))
		guard signature.count == 64,
		      directCiphertext.ciphertext == Data([0x0c, 0x21]),
		      groupCiphertext.senderKeyDistributionMessage == Data([0x22]),
		      directPlaintext == Data([0x0e, 0x23]),
		      groupPlaintext == Data([0x0f, 0x24]),
		      crypto.senderKeyDistributionMessagesCount == 1 else {
			throw ExampleNativeSignalBackendError.selfTestFailed
		}
	}
}

@main
enum Main {
	static func main() async throws {
		if CommandLine.arguments.contains("--self-test") {
			try await NativeSignalBridgeExample.runSelfTest()
			print("NativeSignalBridgeExample self-test passed.")
		}
	}
}

actor ExampleNativeSignalStore: NativeSignalStore {
	private var importedAccounts: [SignalProtocolAddress: NativeSignalAccount] = [:]
	private var installedSessions: [SignalProtocolAddress: NativeSignalSession] = [:]
	private var uploadedPreKeyRequests: [NativePreKeyUploadRequest] = []

	var uploadedPreKeyRequestsCount: Int {
		uploadedPreKeyRequests.count
	}

	func assertReadyForNativeSignalStorage() async throws {
	}

	func importAccount(_ account: NativeSignalAccount) async throws {
		importedAccounts[account.address] = account
	}

	func containsAccount(_ account: NativeSignalAccount) async throws -> Bool {
		importedAccounts[account.address] != nil
	}

	func existingSessions(for checks: [SignalSessionAddressCheck]) async throws -> Set<SignalProtocolAddress> {
		Set(checks.map(\.address).filter { installedSessions[$0] != nil })
	}

	func installSession(_ session: NativeSignalSession) async throws {
		installedSessions[session.address] = session
	}

	func uploadPreKeys(_ request: NativePreKeyUploadRequest) async throws {
		uploadedPreKeyRequests.append(request)
	}
}

struct MissingExampleNativeSignalCryptoProvider: NativeSignalCryptoProvider {
	func signSignedPreKey(identityPrivateKey: Data, signedPreKeyPublicKey: Data) throws -> Data {
		throw ExampleNativeSignalBackendError.backendRequired
	}

	func assertReadyForSignalOperations() async throws {
		throw ExampleNativeSignalBackendError.backendRequired
	}

	func encryptDirectMessage(_ message: NativeDirectMessage) async throws -> NativeDirectCiphertext {
		throw ExampleNativeSignalBackendError.backendRequired
	}

	func encryptGroupMessage(_ message: NativeGroupMessage) async throws -> NativeGroupCiphertext {
		throw ExampleNativeSignalBackendError.backendRequired
	}

	func decryptDirectMessage(_ message: NativeDirectCiphertextMessage) async throws -> Data {
		throw ExampleNativeSignalBackendError.backendRequired
	}

	func decryptGroupMessage(_ message: NativeGroupCiphertextMessage) async throws -> Data {
		throw ExampleNativeSignalBackendError.backendRequired
	}

	func processSenderKeyDistributionMessage(_ message: NativeSenderKeyDistributionMessage) async throws {
		throw ExampleNativeSignalBackendError.backendRequired
	}
}

final class RecordingExampleNativeSignalCryptoProvider: NativeSignalCryptoProvider, @unchecked Sendable {
	private let lock = NSLock()
	private var senderKeyDistributionMessages: [NativeSenderKeyDistributionMessage] = []

	var senderKeyDistributionMessagesCount: Int {
		lock.withLock {
			senderKeyDistributionMessages.count
		}
	}

	func signSignedPreKey(identityPrivateKey: Data, signedPreKeyPublicKey: Data) throws -> Data {
		Data(repeating: 0x20, count: 64)
	}

	func assertReadyForSignalOperations() async throws {}

	func encryptDirectMessage(_ message: NativeDirectMessage) async throws -> NativeDirectCiphertext {
		NativeDirectCiphertext(type: .signalMessage, ciphertext: message.plaintext + Data([0x21]))
	}

	func encryptGroupMessage(_ message: NativeGroupMessage) async throws -> NativeGroupCiphertext {
		NativeGroupCiphertext(
			ciphertext: message.plaintext + Data([0x21]),
			senderKeyDistributionMessage: Data([0x22])
		)
	}

	func decryptDirectMessage(_ message: NativeDirectCiphertextMessage) async throws -> Data {
		message.ciphertext + Data([0x23])
	}

	func decryptGroupMessage(_ message: NativeGroupCiphertextMessage) async throws -> Data {
		message.ciphertext + Data([0x24])
	}

	func processSenderKeyDistributionMessage(_ message: NativeSenderKeyDistributionMessage) async throws {
		lock.withLock {
			senderKeyDistributionMessages.append(message)
		}
	}
}

enum ExampleNativeSignalBackendError: Error {
	case backendRequired
	case selfTestFailed
}

typealias NativeSignalBackend = WhatsAppNativeSignalBackend
typealias NativeSignalRuntime = WhatsAppNativeSignalRuntime
typealias NativeSignalStore = WhatsAppNativeSignalStore
typealias NativeSignalCryptoProvider = WhatsAppNativeSignalCryptoProvider
typealias NativeSignalAccount = WhatsAppNativeSignalAccount
typealias NativeSignalSession = WhatsAppNativeSignalSession
typealias NativeDirectMessage = WhatsAppNativeDirectMessage
typealias NativeGroupMessage = WhatsAppNativeGroupMessage
typealias NativeDirectCiphertext = WhatsAppNativeDirectCiphertext
typealias NativeGroupCiphertext = WhatsAppNativeGroupCiphertext
typealias NativeDirectCiphertextMessage = WhatsAppNativeDirectCiphertextMessage
typealias NativeGroupCiphertextMessage = WhatsAppNativeGroupCiphertextMessage
typealias NativeSenderKeyDistributionMessage = WhatsAppNativeSenderKeyDistributionMessage
typealias NativePreKeyUploadRequest = SignalNativePreKeyUploadRequest
