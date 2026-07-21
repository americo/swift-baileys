import Foundation

public struct AuthenticationState: Sendable {
	public var credentials: AuthenticationCredentials
	public var keys: any SignalKeyStore
	private let saveCredentials: @Sendable (AuthenticationCredentials) async throws -> Void

	public var transactionalKeys: (any SignalKeyStoreWithTransactions)? {
		keys as? any SignalKeyStoreWithTransactions
	}

	public init(
		credentials: AuthenticationCredentials,
		keys: any SignalKeyStore,
		saveCredentials: @escaping @Sendable (AuthenticationCredentials) async throws -> Void = { _ in }
	) {
		self.credentials = credentials
		self.keys = keys
		self.saveCredentials = saveCredentials
	}

	public mutating func updateCredentials(
		_ update: @Sendable (inout AuthenticationCredentials) throws -> Void
	) async throws {
		var nextCredentials = credentials
		try update(&nextCredentials)
		try await saveCredentials(nextCredentials)
		credentials = nextCredentials
	}

	public static func loadOrCreate(
		store: FileAuthenticationStore,
		credentialsFactory: @Sendable () throws -> AuthenticationCredentials
	) async throws -> AuthenticationState {
		if let credentials = try await store.loadCredentials() {
			return AuthenticationState(
				credentials: credentials,
				keys: TransactionalSignalKeyStore(store: CacheableSignalKeyStore(store: store.keys)),
				saveCredentials: store.saveCredentials
			)
		}

		let credentials = try credentialsFactory()
		try await store.saveCredentials(credentials)
		return AuthenticationState(
			credentials: credentials,
			keys: TransactionalSignalKeyStore(store: CacheableSignalKeyStore(store: store.keys)),
			saveCredentials: store.saveCredentials
		)
	}
}
