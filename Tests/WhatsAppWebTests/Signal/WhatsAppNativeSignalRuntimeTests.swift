import Foundation
import Testing
import WhatsAppWeb

@Suite("WhatsApp native Signal runtime")
struct WhatsAppNativeSignalRuntimeTests {
	@Test("builds client auth and imports native account after pairing")
	func buildsClientAuthAndImportsNativeAccountAfterPairing() async throws {
		let backend = RuntimeWhatsAppNativeSignalBackend()
		let authStore = FileAuthenticationStore(directory: temporaryAuthDirectory())
		let runtime = try await WhatsAppNativeSignalRuntime.make(
			authStore: authStore,
			backend: backend,
			mediaUploader: { _ in PublicMediaUploader() }
		)

		try await runtime.client.updateCredentials { credentials in
			credentials.me = WhatsAppUser(id: "999:0@s.whatsapp.net")
			credentials.registered = true
		}
		let credentials = try #require(await runtime.client.authenticationState?.credentials)
		let result = try await runtime.handleEvent(.credentialsUpdated(credentials))
		let report = try await runtime.readinessReport()

		#expect(result?.imported == true)
		#expect(result?.request.localAddress == SignalProtocolAddress(name: "999", deviceID: 0))
		#expect(report.isReady)
		#expect(await backend.importedAccounts.map(\.address) == [
			SignalProtocolAddress(name: "999", deviceID: 0)
		])
		#expect(await backend.readinessCheckCount == 3)
		#expect(backend.signedPreKeyPublicKeys.count == 4)
		#expect(backend.signedPreKeyPublicKeys.allSatisfy { $0.count == 32 })
	}

	@Test("runtime composes native Signal store and crypto provider directly")
	func runtimeComposesNativeSignalStoreAndCryptoProviderDirectly() async throws {
		let store = RuntimeWhatsAppNativeSignalStore()
		let crypto = RuntimeWhatsAppNativeSignalCryptoProvider()
		let authStore = FileAuthenticationStore(directory: temporaryAuthDirectory())
		let runtime = try await WhatsAppNativeSignalRuntime.make(
			authStore: authStore,
			store: store,
			cryptoProvider: crypto,
			mediaUploader: { _ in PublicMediaUploader() }
		)

		try await runtime.client.updateCredentials { credentials in
			credentials.me = WhatsAppUser(id: "999:0@s.whatsapp.net")
			credentials.registered = true
		}
		let credentials = try #require(await runtime.client.authenticationState?.credentials)
		let result = try await runtime.handleEvent(.credentialsUpdated(credentials))

		#expect(result?.imported == true)
		#expect(await store.importedAccounts.map(\.address) == [
			SignalProtocolAddress(name: "999", deviceID: 0)
		])
		#expect(await store.readinessCheckCount >= 1)
		#expect(await crypto.readinessCheckCount >= 1)
		#expect(crypto.signedPreKeyPublicKeys.allSatisfy { $0.count == 32 })
	}

	@Test("readiness monitor imports native account from credential events")
	func readinessMonitorImportsNativeAccountFromCredentialEvents() async throws {
		let backend = RuntimeWhatsAppNativeSignalBackend()
		let authStore = FileAuthenticationStore(directory: temporaryAuthDirectory())
		let runtime = try await WhatsAppNativeSignalRuntime.make(
			authStore: authStore,
			backend: backend,
			mediaUploader: { _ in PublicMediaUploader() }
		)

		try await runtime.client.updateCredentials { credentials in
			credentials.me = WhatsAppUser(id: "999:0@s.whatsapp.net")
			credentials.registered = true
		}
		let credentials = try #require(await runtime.client.authenticationState?.credentials)
		let events = AsyncStream<WhatsAppClientEvent> { continuation in
			continuation.yield(.newLogin)
			continuation.yield(.credentialsUpdated(credentials))
			continuation.finish()
		}

		try await runtime.runReadinessMonitor(events: events)

		#expect(await backend.importedAccounts.map(\.address) == [
			SignalProtocolAddress(name: "999", deviceID: 0)
		])
	}

	@Test("runtime can import native account when paired credentials already exist")
	func runtimeCanImportNativeAccountWhenPairedCredentialsAlreadyExist() async throws {
		let backend = RuntimeWhatsAppNativeSignalBackend()
		let authStore = FileAuthenticationStore(directory: temporaryAuthDirectory())
		try await authStore.saveCredentials(publicNativePairedCredentials())

		_ = try await WhatsAppNativeSignalRuntime.make(
			authStore: authStore,
			backend: backend,
			ensureReadyForMessagingOnLoad: true,
			mediaUploader: { _ in PublicMediaUploader() }
		)

		#expect(await backend.importedAccounts.map(\.address) == [
			SignalProtocolAddress(name: "999", deviceID: 0)
		])
		#expect(await backend.readinessCheckCount == 2)
	}

	@Test("readiness monitor imports already paired current credentials before events")
	func readinessMonitorImportsAlreadyPairedCurrentCredentialsBeforeEvents() async throws {
		let backend = RuntimeWhatsAppNativeSignalBackend()
		let authStore = FileAuthenticationStore(directory: temporaryAuthDirectory())
		try await authStore.saveCredentials(publicNativePairedCredentials())
		let runtime = try await WhatsAppNativeSignalRuntime.make(
			authStore: authStore,
			backend: backend,
			mediaUploader: { _ in PublicMediaUploader() }
		)
		let events = AsyncStream<WhatsAppClientEvent> { continuation in
			continuation.finish()
		}

		try await runtime.runReadinessMonitor(events: events)

		#expect(await backend.importedAccounts.map(\.address) == [
			SignalProtocolAddress(name: "999", deviceID: 0)
		])
	}

	@Test("runtime fails before auth setup when native backend preflight fails")
	func runtimeFailsBeforeAuthSetupWhenNativeBackendPreflightFails() async throws {
		let backend = RuntimeWhatsAppNativeSignalBackend(readinessError: NativeBackendReadinessTestError.notReady)
		let authDirectory = temporaryAuthDirectory()
		let authStore = FileAuthenticationStore(directory: authDirectory)

		await #expect(throws: NativeBackendReadinessTestError.notReady) {
			_ = try await WhatsAppNativeSignalRuntime.make(
				authStore: authStore,
				backend: backend,
				mediaUploader: { _ in PublicMediaUploader() }
			)
		}

		#expect(await backend.readinessCheckCount == 1)
		#expect(!FileManager.default.fileExists(atPath: authDirectory.path))
	}

	@Test("runtime validates native signed pre-key signing before loading existing auth")
	func runtimeValidatesNativeSignedPreKeySigningBeforeLoadingExistingAuth() async throws {
		let backend = RuntimeWhatsAppNativeSignalBackend(signedPreKeySignature: Data(repeating: 0x51, count: 63))
		let authStore = FileAuthenticationStore(directory: temporaryAuthDirectory())
		try await authStore.saveCredentials(publicNativePairedCredentials())

		await #expect(throws: WhatsAppNativeSignalBackendAdapterError.invalidSignedPreKeySignature) {
			_ = try await WhatsAppNativeSignalRuntime.make(
				authStore: authStore,
				backend: backend,
				mediaUploader: { _ in PublicMediaUploader() }
			)
		}

		#expect(await backend.readinessCheckCount == 1)
		#expect(backend.signedPreKeyPublicKeys.count == 1)
		#expect(backend.signedPreKeyPublicKeys.first?.count == 32)
	}

	@Test("readiness monitor task imports native account from client credential events")
	func readinessMonitorTaskImportsNativeAccountFromClientCredentialEvents() async throws {
		let backend = RuntimeWhatsAppNativeSignalBackend()
		let authStore = FileAuthenticationStore(directory: temporaryAuthDirectory())
		let runtime = try await WhatsAppNativeSignalRuntime.make(
			authStore: authStore,
			backend: backend,
			mediaUploader: { _ in PublicMediaUploader() }
		)
		let monitorTask = runtime.startReadinessMonitor()

		try await runtime.client.updateCredentials { credentials in
			credentials.me = WhatsAppUser(id: "999:0@s.whatsapp.net")
			credentials.registered = true
		}
		for _ in 0..<50 {
			if await !backend.importedAccounts.isEmpty { break }
			try await Task.sleep(for: .milliseconds(10))
		}
		monitorTask.cancel()

		#expect(await backend.importedAccounts.map(\.address) == [
			SignalProtocolAddress(name: "999", deviceID: 0)
		])
	}

	@Test("managed readiness monitor can be cancelled through the runtime")
	func managedReadinessMonitorCanBeCancelledThroughRuntime() async throws {
		let backend = RuntimeWhatsAppNativeSignalBackend()
		let authStore = FileAuthenticationStore(directory: temporaryAuthDirectory())
		let runtime = try await WhatsAppNativeSignalRuntime.make(
			authStore: authStore,
			backend: backend,
			mediaUploader: { _ in PublicMediaUploader() }
		)

		await runtime.startManagedReadinessMonitor()
		try await runtime.client.updateCredentials { credentials in
			credentials.me = WhatsAppUser(id: "999:0@s.whatsapp.net")
			credentials.registered = true
		}
		for _ in 0..<50 {
			if await backend.importedAccounts.count == 1 { break }
			try await Task.sleep(for: .milliseconds(10))
		}

		await runtime.stopManagedReadinessMonitor()
		try await runtime.client.updateCredentials { credentials in
			credentials.me = WhatsAppUser(id: "888:0@s.whatsapp.net")
			credentials.registered = true
		}
		try await Task.sleep(for: .milliseconds(50))

		#expect(await backend.importedAccounts.map(\.address) == [
			SignalProtocolAddress(name: "999", deviceID: 0)
		])
	}

	@Test("managed readiness monitor exposes background failures")
	func managedReadinessMonitorExposesBackgroundFailures() async throws {
		let backend = RuntimeWhatsAppNativeSignalBackend(importError: NativeBackendImportTestError.failed)
		let authStore = FileAuthenticationStore(directory: temporaryAuthDirectory())
		let runtime = try await WhatsAppNativeSignalRuntime.make(
			authStore: authStore,
			backend: backend,
			mediaUploader: { _ in PublicMediaUploader() }
		)

		await runtime.startManagedReadinessMonitor()
		#expect(await runtime.managedReadinessMonitorStatus() == .running)
		try await runtime.client.updateCredentials { credentials in
			credentials.me = WhatsAppUser(id: "999:0@s.whatsapp.net")
			credentials.registered = true
		}
		for _ in 0..<50 {
			if await runtime.managedReadinessMonitorStatus() == .failed("NativeBackendImportTestError") { break }
			try await Task.sleep(for: .milliseconds(10))
		}

		#expect(await runtime.managedReadinessMonitorStatus() == .failed("NativeBackendImportTestError"))
		#expect(await backend.importedAccounts.isEmpty)
	}

	@Test("ignores non credential events")
	func ignoresNonCredentialEvents() async throws {
		let runtime = WhatsAppNativeSignalRuntime(
			client: WhatsAppClient(),
			signalAdapter: WhatsAppNativeSignalBackendAdapter(backend: RuntimeWhatsAppNativeSignalBackend())
		)

		let result = try await runtime.handleEvent(.newLogin)

		#expect(result == nil)
	}
}

private actor RuntimeWhatsAppNativeSignalBackend: WhatsAppNativeSignalBackend {
	private let readinessError: (any Error)?
	private let importError: (any Error)?
	private let signedPreKeySignature: Data
	private var importedAddresses = Set<SignalProtocolAddress>()
	private(set) var importedAccounts: [WhatsAppNativeSignalAccount] = []
	private(set) var readinessCheckCount = 0
	nonisolated private let signedPreKeyPublicKeyRecorder = PublicNativeRequestRecorder<Data>()
	nonisolated var signedPreKeyPublicKeys: [Data] {
		signedPreKeyPublicKeyRecorder.values
	}

	init(
		readinessError: (any Error)? = nil,
		importError: (any Error)? = nil,
		signedPreKeySignature: Data = Data(repeating: 0x51, count: 64)
	) {
		self.readinessError = readinessError
		self.importError = importError
		self.signedPreKeySignature = signedPreKeySignature
	}

	nonisolated func signSignedPreKey(identityPrivateKey: Data, signedPreKeyPublicKey: Data) throws -> Data {
		signedPreKeyPublicKeyRecorder.record(signedPreKeyPublicKey)
		return signedPreKeySignature
	}

	func assertReadyForSignalOperations() async throws {
		readinessCheckCount += 1
		if let readinessError {
			throw readinessError
		}
	}

	func importAccount(_ account: WhatsAppNativeSignalAccount) async throws {
		if let importError {
			throw importError
		}
		importedAccounts.append(account)
		importedAddresses.insert(account.address)
	}

	func containsAccount(_ account: WhatsAppNativeSignalAccount) async throws -> Bool {
		importedAddresses.contains(account.address)
	}

	func existingSessions(for checks: [SignalSessionAddressCheck]) async throws -> Set<SignalProtocolAddress> {
		Set(checks.map(\.address))
	}

	func installSession(_ session: WhatsAppNativeSignalSession) async throws {}

	func encryptDirectMessage(_ message: WhatsAppNativeDirectMessage) async throws -> WhatsAppNativeDirectCiphertext {
		WhatsAppNativeDirectCiphertext(type: .signalMessage, ciphertext: message.plaintext)
	}

	func encryptGroupMessage(_ message: WhatsAppNativeGroupMessage) async throws -> WhatsAppNativeGroupCiphertext {
		WhatsAppNativeGroupCiphertext(
			ciphertext: message.plaintext,
			senderKeyDistributionMessage: Data([0x01])
		)
	}

	func decryptDirectMessage(_ message: WhatsAppNativeDirectCiphertextMessage) async throws -> Data {
		message.ciphertext
	}

	func decryptGroupMessage(_ message: WhatsAppNativeGroupCiphertextMessage) async throws -> Data {
		message.ciphertext
	}

	func processSenderKeyDistributionMessage(_ message: WhatsAppNativeSenderKeyDistributionMessage) async throws {}

	func uploadPreKeys(_ request: SignalNativePreKeyUploadRequest) async throws {}
}

private actor RuntimeWhatsAppNativeSignalStore: WhatsAppNativeSignalStore {
	private var importedAddresses = Set<SignalProtocolAddress>()
	private(set) var importedAccounts: [WhatsAppNativeSignalAccount] = []
	private(set) var readinessCheckCount = 0

	func assertReadyForNativeSignalStorage() async throws {
		readinessCheckCount += 1
	}

	func importAccount(_ account: WhatsAppNativeSignalAccount) async throws {
		importedAccounts.append(account)
		importedAddresses.insert(account.address)
	}

	func containsAccount(_ account: WhatsAppNativeSignalAccount) async throws -> Bool {
		importedAddresses.contains(account.address)
	}

	func existingSessions(for checks: [SignalSessionAddressCheck]) async throws -> Set<SignalProtocolAddress> {
		Set(checks.map(\.address))
	}

	func installSession(_ session: WhatsAppNativeSignalSession) async throws {}

	func uploadPreKeys(_ request: SignalNativePreKeyUploadRequest) async throws {}
}

private actor RuntimeWhatsAppNativeSignalCryptoProvider: WhatsAppNativeSignalCryptoProvider {
	private(set) var readinessCheckCount = 0
	nonisolated private let signedPreKeyPublicKeyRecorder = PublicNativeRequestRecorder<Data>()
	nonisolated var signedPreKeyPublicKeys: [Data] {
		signedPreKeyPublicKeyRecorder.values
	}

	nonisolated func signSignedPreKey(identityPrivateKey: Data, signedPreKeyPublicKey: Data) throws -> Data {
		signedPreKeyPublicKeyRecorder.record(signedPreKeyPublicKey)
		return Data(repeating: 0x51, count: 64)
	}

	func assertReadyForSignalOperations() async throws {
		readinessCheckCount += 1
	}

	func encryptDirectMessage(_ message: WhatsAppNativeDirectMessage) async throws -> WhatsAppNativeDirectCiphertext {
		WhatsAppNativeDirectCiphertext(type: .signalMessage, ciphertext: message.plaintext)
	}

	func encryptGroupMessage(_ message: WhatsAppNativeGroupMessage) async throws -> WhatsAppNativeGroupCiphertext {
		WhatsAppNativeGroupCiphertext(
			ciphertext: message.plaintext,
			senderKeyDistributionMessage: Data([0x01])
		)
	}

	func decryptDirectMessage(_ message: WhatsAppNativeDirectCiphertextMessage) async throws -> Data {
		message.ciphertext
	}

	func decryptGroupMessage(_ message: WhatsAppNativeGroupCiphertextMessage) async throws -> Data {
		message.ciphertext
	}

	func processSenderKeyDistributionMessage(_ message: WhatsAppNativeSenderKeyDistributionMessage) async throws {}
}

private func temporaryAuthDirectory() -> URL {
	FileManager.default.temporaryDirectory
		.appendingPathComponent("SwiftBaileysTests")
		.appendingPathComponent(UUID().uuidString)
}

private enum NativeBackendReadinessTestError: Error, Equatable {
	case notReady
}

private enum NativeBackendImportTestError: Error, Equatable {
	case failed
}
