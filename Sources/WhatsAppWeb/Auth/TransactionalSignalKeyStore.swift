import Foundation

public struct SignalKeyTransactionOptions: Equatable, Sendable {
	public let maxCommitRetries: Int
	public let delayBetweenRetries: Duration

	public init(maxCommitRetries: Int = 10, delayBetweenRetries: Duration = .seconds(3)) {
		self.maxCommitRetries = maxCommitRetries
		self.delayBetweenRetries = delayBetweenRetries
	}
}

public protocol SignalKeyStoreWithTransactions: SignalKeyStore {
	func transaction<T: Sendable>(
		key: String,
		_ work: @Sendable (any SignalKeyStore) async throws -> T
	) async throws -> T
}

public actor TransactionalSignalKeyStore: SignalKeyStoreWithTransactions {
	private let store: any SignalKeyStore
	private let options: SignalKeyTransactionOptions

	public init(store: any SignalKeyStore, options: SignalKeyTransactionOptions = SignalKeyTransactionOptions()) {
		self.store = store
		self.options = options
	}

	public func get(_ category: SignalKeyCategory, ids: [String]) async throws -> [String: Data] {
		try await store.get(category, ids: ids)
	}

	public func set(_ values: [SignalKeyCategory: [String: Data?]]) async throws {
		try await store.set(values)
	}

	public func clear() async throws {
		try await store.clear()
	}

	public func transaction<T: Sendable>(
		key _: String,
		_ work: @Sendable (any SignalKeyStore) async throws -> T
	) async throws -> T {
		let context = SignalKeyTransactionContext(store: store)
		let result = try await work(context)
		let snapshot = await context.snapshot()
		try await commit(snapshot)
		return result
	}

	private func commit(_ snapshot: SignalKeyTransactionSnapshot) async throws {
		guard snapshot.clearsStore || !snapshot.mutations.isEmpty else {
			return
		}

		let attempts = max(1, options.maxCommitRetries)
		for attempt in 1...attempts {
			do {
				if snapshot.clearsStore {
					try await store.clear()
				}
				if !snapshot.mutations.isEmpty {
					try await store.set(snapshot.mutations)
				}
				return
			} catch {
				if attempt == attempts {
					throw error
				}

				try await Task.sleep(for: options.delayBetweenRetries)
			}
		}
	}
}

private struct SignalKeyTransactionSnapshot: Sendable {
	let clearsStore: Bool
	let mutations: [SignalKeyCategory: [String: Data?]]
}

private actor SignalKeyTransactionContext: SignalKeyStore {
	private let store: any SignalKeyStore
	private var cache: [SignalKeyCategory: [String: Data?]] = [:]
	private var stagedMutations: [SignalKeyCategory: [String: Data?]] = [:]
	private var clearsStore = false

	func snapshot() -> SignalKeyTransactionSnapshot {
		SignalKeyTransactionSnapshot(clearsStore: clearsStore, mutations: stagedMutations)
	}

	init(store: any SignalKeyStore) {
		self.store = store
	}

	func get(_ category: SignalKeyCategory, ids: [String]) async throws -> [String: Data] {
		var values = cache[category] ?? [:]
		let missing = ids.filter { !values.keys.contains($0) }
		if !missing.isEmpty && !clearsStore {
			let fetched = try await store.get(category, ids: missing)
			for id in missing {
				values[id] = fetched[id]
			}
		}

		cache[category] = values
		return ids.reduce(into: [:]) { result, id in
			if let value = values[id] ?? nil {
				result[id] = value
			}
		}
	}

	func set(_ values: [SignalKeyCategory: [String: Data?]]) async throws {
		for (category, updates) in values {
			var categoryCache = cache[category] ?? [:]
			var categoryMutations = stagedMutations[category] ?? [:]

			for (id, value) in updates {
				categoryCache[id] = value
				categoryMutations[id] = value
			}

			cache[category] = categoryCache
			stagedMutations[category] = categoryMutations
		}
	}

	func clear() async throws {
		clearsStore = true
		cache.removeAll()
		stagedMutations.removeAll()
	}
}
