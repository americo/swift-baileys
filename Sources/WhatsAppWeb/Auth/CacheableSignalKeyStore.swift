import Foundation

public actor CacheableSignalKeyStore: SignalKeyStore {
	private struct Entry {
		let value: Data
		let expiresAt: Date
	}

	private let store: any SignalKeyStore
	private let ttl: TimeInterval
	private let now: @Sendable () -> Date
	private var cache: [SignalKeyCategory: [String: Entry]] = [:]

	public init(
		store: any SignalKeyStore,
		ttl: TimeInterval = 300,
		now: @escaping @Sendable () -> Date = Date.init
	) {
		self.store = store
		self.ttl = ttl
		self.now = now
	}

	public func get(_ category: SignalKeyCategory, ids: [String]) async throws -> [String: Data] {
		let currentDate = now()
		var values = cache[category] ?? [:]
		var result: [String: Data] = [:]
		var missing: [String] = []

		for id in ids {
			if let entry = values[id], entry.expiresAt > currentDate {
				result[id] = entry.value
			} else {
				values.removeValue(forKey: id)
				missing.append(id)
			}
		}

		cache[category] = values
		if missing.isEmpty {
			return result
		}

		let fetched = try await store.get(category, ids: missing)
		for (id, value) in fetched {
			result[id] = value
			values[id] = Entry(value: value, expiresAt: currentDate.addingTimeInterval(ttl))
		}

		cache[category] = values
		return result
	}

	public func set(_ values: [SignalKeyCategory: [String: Data?]]) async throws {
		let currentDate = now()
		for (category, updates) in values {
			var categoryCache = cache[category] ?? [:]
			for (id, value) in updates {
				if let value {
					categoryCache[id] = Entry(value: value, expiresAt: currentDate.addingTimeInterval(ttl))
				} else {
					categoryCache.removeValue(forKey: id)
				}
			}

			cache[category] = categoryCache
		}

		try await store.set(values)
	}

	public func clear() async throws {
		cache.removeAll()
		try await store.clear()
	}
}
