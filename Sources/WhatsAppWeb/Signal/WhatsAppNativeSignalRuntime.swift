import Foundation

public enum WhatsAppNativeSignalReadinessMonitorStatus: Equatable, Sendable {
	case idle
	case running
	case completed
	case failed(String)
}

public struct WhatsAppNativeSignalRuntime: Sendable {
	public let client: WhatsAppClient
	public let signalAdapter: WhatsAppNativeSignalBackendAdapter
	private let readinessMonitor = WhatsAppNativeSignalReadinessMonitorStore()

	public init(client: WhatsAppClient, signalAdapter: WhatsAppNativeSignalBackendAdapter) {
		self.client = client
		self.signalAdapter = signalAdapter
	}

	public static func make(
		authDirectory: URL,
		store: any WhatsAppNativeSignalStore,
		cryptoProvider: any WhatsAppNativeSignalCryptoProvider,
		configuration: WhatsAppClientConfiguration = WhatsAppClientConfiguration(),
		pairSuccessProcessor: (any PairSuccessProcessing)? = nil,
		ensureReadyForMessagingOnLoad: Bool = false,
		transportFactory: @escaping @Sendable (URL) -> any WhatsAppWebSocketTransport = {
			URLSessionWebSocketTransport(url: $0)
		}
	) async throws -> WhatsAppNativeSignalRuntime {
		try await make(
			authStore: FileAuthenticationStore(directory: authDirectory),
			store: store,
			cryptoProvider: cryptoProvider,
			configuration: configuration,
			pairSuccessProcessor: pairSuccessProcessor,
			ensureReadyForMessagingOnLoad: ensureReadyForMessagingOnLoad,
			transportFactory: transportFactory
		)
	}

	public static func make(
		authDirectory: URL,
		backend: any WhatsAppNativeSignalBackend,
		configuration: WhatsAppClientConfiguration = WhatsAppClientConfiguration(),
		pairSuccessProcessor: (any PairSuccessProcessing)? = nil,
		ensureReadyForMessagingOnLoad: Bool = false,
		transportFactory: @escaping @Sendable (URL) -> any WhatsAppWebSocketTransport = {
			URLSessionWebSocketTransport(url: $0)
		}
	) async throws -> WhatsAppNativeSignalRuntime {
		try await make(
			authStore: FileAuthenticationStore(directory: authDirectory),
			backend: backend,
			configuration: configuration,
			pairSuccessProcessor: pairSuccessProcessor,
			ensureReadyForMessagingOnLoad: ensureReadyForMessagingOnLoad,
			transportFactory: transportFactory
		)
	}

	public static func make(
		authStore: FileAuthenticationStore,
		store: any WhatsAppNativeSignalStore,
		cryptoProvider: any WhatsAppNativeSignalCryptoProvider,
		configuration: WhatsAppClientConfiguration = WhatsAppClientConfiguration(),
		pairSuccessProcessor: (any PairSuccessProcessing)? = nil,
		ensureReadyForMessagingOnLoad: Bool = false,
		transportFactory: @escaping @Sendable (URL) -> any WhatsAppWebSocketTransport = {
			URLSessionWebSocketTransport(url: $0)
		},
		mediaUploader: ((WhatsAppClient) -> any WhatsAppMediaUploading)? = nil
	) async throws -> WhatsAppNativeSignalRuntime {
		try await make(
			authStore: authStore,
			backend: WhatsAppComposedNativeSignalBackend(
				store: store,
				cryptoProvider: cryptoProvider
			),
			configuration: configuration,
			pairSuccessProcessor: pairSuccessProcessor,
			ensureReadyForMessagingOnLoad: ensureReadyForMessagingOnLoad,
			transportFactory: transportFactory,
			mediaUploader: mediaUploader
		)
	}

	public static func make(
		authStore: FileAuthenticationStore,
		backend: any WhatsAppNativeSignalBackend,
		configuration: WhatsAppClientConfiguration = WhatsAppClientConfiguration(),
		pairSuccessProcessor: (any PairSuccessProcessing)? = nil,
		ensureReadyForMessagingOnLoad: Bool = false,
		transportFactory: @escaping @Sendable (URL) -> any WhatsAppWebSocketTransport = {
			URLSessionWebSocketTransport(url: $0)
		},
		mediaUploader: ((WhatsAppClient) -> any WhatsAppMediaUploading)? = nil
	) async throws -> WhatsAppNativeSignalRuntime {
		let signalAdapter = WhatsAppNativeSignalBackendAdapter(backend: backend)
		try await signalAdapter.assertReadyForSignalOperations()
		try signalAdapter.assertReadyForCredentialSigning()
		let credentialsFactory = AuthenticationCredentialsFactory(nativeSignalAdapter: signalAdapter)
		let authState = try await AuthenticationState.loadOrCreate(
			store: authStore,
			credentialsFactory: credentialsFactory.makeCredentials
		)
		let client = WhatsAppClient(
			configuration: configuration,
			authenticationState: authState,
			pairSuccessProcessor: pairSuccessProcessor,
			transportFactory: transportFactory
		)
		await client.configureNativeSignalAdapter(
			signalAdapter,
			mediaUploader: mediaUploader?(client) ?? WhatsAppMediaUploader(query: client.query(_:timeout:))
		)
		let runtime = WhatsAppNativeSignalRuntime(client: client, signalAdapter: signalAdapter)
		if ensureReadyForMessagingOnLoad, authState.credentials.me != nil {
			_ = try await runtime.ensureReadyForMessaging()
		}
		return runtime
	}

	public func handleEvent(
		_ event: WhatsAppClientEvent,
		capabilities: Set<WhatsAppClientMessageCapability> = Set(WhatsAppClientMessageCapability.allCases)
	) async throws -> SignalNativeAccountImportResult? {
		guard case .credentialsUpdated(let credentials) = event, credentials.me != nil else {
			return nil
		}

		return try await ensureReadyForMessaging(capabilities: capabilities)
	}

	public func runReadinessMonitor(
		capabilities: Set<WhatsAppClientMessageCapability> = Set(WhatsAppClientMessageCapability.allCases)
	) async throws {
		try await runReadinessMonitor(events: client.events, capabilities: capabilities)
	}

	public func startReadinessMonitor(
		capabilities: Set<WhatsAppClientMessageCapability> = Set(WhatsAppClientMessageCapability.allCases)
	) -> Task<Void, any Error> {
		Task {
			try await runReadinessMonitor(capabilities: capabilities)
		}
	}

	public func startManagedReadinessMonitor(
		capabilities: Set<WhatsAppClientMessageCapability> = Set(WhatsAppClientMessageCapability.allCases)
	) async {
		let generation = await readinessMonitor.start()
		let readinessMonitor = readinessMonitor
		let task = Task {
			do {
				try await runReadinessMonitor(capabilities: capabilities)
				await readinessMonitor.finish(.completed, generation: generation)
			} catch {
				if !Task.isCancelled {
					await readinessMonitor.finish(.failed(String(describing: type(of: error))), generation: generation)
				}
				throw error
			}
		}
		await readinessMonitor.attach(task, generation: generation)
	}

	public func stopManagedReadinessMonitor() async {
		await readinessMonitor.cancel()
	}

	public func managedReadinessMonitorStatus() async -> WhatsAppNativeSignalReadinessMonitorStatus {
		await readinessMonitor.currentStatus()
	}

	public func runReadinessMonitor<EventStream: AsyncSequence>(
		events: EventStream,
		capabilities: Set<WhatsAppClientMessageCapability> = Set(WhatsAppClientMessageCapability.allCases)
	) async throws where EventStream.Element == WhatsAppClientEvent {
		if await client.authenticationState?.credentials.me != nil {
			_ = try await ensureReadyForMessaging(capabilities: capabilities)
		}

		for try await event in events {
			_ = try await handleEvent(event, capabilities: capabilities)
		}
	}

	public func ensureReadyForMessaging(
		capabilities: Set<WhatsAppClientMessageCapability> = Set(WhatsAppClientMessageCapability.allCases)
	) async throws -> SignalNativeAccountImportResult {
		try await client.ensureNativeMessageReadiness(
			capabilities: capabilities,
			using: signalAdapter
		)
	}

	public func readinessReport(
		capabilities: Set<WhatsAppClientMessageCapability> = Set(WhatsAppClientMessageCapability.allCases)
	) async throws -> WhatsAppClientNativeMessageReadinessReport {
		try await client.nativeMessageReadinessReport(
			capabilities: capabilities,
			using: signalAdapter
		)
	}
}

private actor WhatsAppNativeSignalReadinessMonitorStore {
	private var task: Task<Void, any Error>?
	private var generation = 0
	private var status = WhatsAppNativeSignalReadinessMonitorStatus.idle

	func start() -> Int {
		task?.cancel()
		generation += 1
		task = nil
		status = .running
		return generation
	}

	func attach(_ newTask: Task<Void, any Error>, generation taskGeneration: Int) {
		guard taskGeneration == generation else {
			newTask.cancel()
			return
		}

		task = newTask
	}

	func cancel() {
		task?.cancel()
		task = nil
		status = .idle
	}

	func finish(_ finalStatus: WhatsAppNativeSignalReadinessMonitorStatus, generation taskGeneration: Int) {
		guard taskGeneration == generation else {
			return
		}

		task = nil
		status = finalStatus
	}

	func currentStatus() -> WhatsAppNativeSignalReadinessMonitorStatus {
		status
	}
}
