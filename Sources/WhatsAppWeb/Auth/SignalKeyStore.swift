import Foundation

public enum SignalKeyCategory: String, Codable, CaseIterable, Sendable {
	case preKey = "pre-key"
	case session
	case senderKey = "sender-key"
	case senderKeyMemory = "sender-key-memory"
	case appStateSyncKey = "app-state-sync-key"
	case appStateSyncVersion = "app-state-sync-version"
	case lidMapping = "lid-mapping"
	case deviceList = "device-list"
	case tcToken = "tctoken"
	case identityKey = "identity-key"
}

public protocol SignalKeyStore: Sendable {
	func get(_ category: SignalKeyCategory, ids: [String]) async throws -> [String: Data]
	func set(_ values: [SignalKeyCategory: [String: Data?]]) async throws
	func clear() async throws
}

public actor InMemorySignalKeyStore: SignalKeyStore {
	private var storage: [SignalKeyCategory: [String: Data]]

	public init(storage: [SignalKeyCategory: [String: Data]] = [:]) {
		self.storage = storage
	}

	public func get(_ category: SignalKeyCategory, ids: [String]) async throws -> [String: Data] {
		let values = storage[category] ?? [:]
		var result: [String: Data] = [:]

		for id in ids {
			if let value = values[id] {
				result[id] = value
			}
		}

		return result
	}

	public func set(_ values: [SignalKeyCategory: [String: Data?]]) async throws {
		for (category, updates) in values {
			var categoryValues = storage[category] ?? [:]

			for (id, value) in updates {
				if let value {
					categoryValues[id] = value
				} else {
					categoryValues.removeValue(forKey: id)
				}
			}

			storage[category] = categoryValues
		}
	}

	public func clear() async throws {
		storage.removeAll()
	}
}
