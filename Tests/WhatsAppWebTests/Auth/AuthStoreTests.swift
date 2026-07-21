import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Auth store")
struct AuthStoreTests {
	@Test("memory key store returns saved keys and removes nil updates")
	func memoryKeyStoreReturnsSavedKeysAndRemovesNilUpdates() async throws {
		let store = InMemorySignalKeyStore()
		let session = Data([1, 2, 3])
		let identity = Data([4, 5, 6])

		try await store.set([
			.session: ["alice:0": session],
			.identityKey: ["alice": identity]
		])

		#expect(try await store.get(.session, ids: ["alice:0", "missing"]) == ["alice:0": session])
		#expect(try await store.get(.identityKey, ids: ["alice"]) == ["alice": identity])

		try await store.set([.session: ["alice:0": nil]])

		#expect(try await store.get(.session, ids: ["alice:0"]).isEmpty)
	}

	@Test("file auth store persists credentials and signal keys")
	func fileAuthStorePersistsCredentialsAndSignalKeys() async throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("swift-baileys-auth-\(UUID().uuidString)", isDirectory: true)
		let store = FileAuthenticationStore(directory: directory)
		let credentials = sampleCredentials()
		let session = Data([9, 8, 7])

		try await store.saveCredentials(credentials)
		try await store.keys.set([.session: ["user/phone:0": session]])

		let reloaded = FileAuthenticationStore(directory: directory)

		#expect(try await reloaded.loadCredentials() == credentials)
		#expect(try await reloaded.keys.get(.session, ids: ["user/phone:0"]) == ["user/phone:0": session])
		#expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("session-dXNlci9waG9uZTow.json").path))
	}

	@Test("cacheable key store reuses cached keys and fetches only misses")
	func cacheableKeyStoreReusesCachedKeysAndFetchesOnlyMisses() async throws {
		let backing = CountingSignalKeyStore(storage: [.session: [
			"alice.0": Data([1]),
			"bob.0": Data([2])
		]])
		let store = CacheableSignalKeyStore(store: backing)

		#expect(try await store.get(.session, ids: ["alice.0"]) == ["alice.0": Data([1])])
		#expect(try await store.get(.session, ids: ["alice.0", "bob.0"]) == [
			"alice.0": Data([1]),
			"bob.0": Data([2])
		])

		#expect(await backing.getRequests == [
			SignalKeyStoreGetRequest(category: .session, ids: ["alice.0"]),
			SignalKeyStoreGetRequest(category: .session, ids: ["bob.0"])
		])
	}

	@Test("cacheable key store writes through and invalidates removed keys")
	func cacheableKeyStoreWritesThroughAndInvalidatesRemovedKeys() async throws {
		let backing = CountingSignalKeyStore()
		let store = CacheableSignalKeyStore(store: backing)

		try await store.set([.session: ["alice.0": Data([1])]])
		#expect(try await backing.get(.session, ids: ["alice.0"]) == ["alice.0": Data([1])])
		#expect(try await store.get(.session, ids: ["alice.0"]) == ["alice.0": Data([1])])

		try await store.set([.session: ["alice.0": nil]])

		#expect(try await store.get(.session, ids: ["alice.0"]).isEmpty)
		#expect(try await backing.get(.session, ids: ["alice.0"]).isEmpty)
	}

	@Test("cacheable key store refetches expired keys")
	func cacheableKeyStoreRefetchesExpiredKeys() async throws {
		let clock = MutableClock(date: Date(timeIntervalSince1970: 1_700_000_000))
		let backing = CountingSignalKeyStore(storage: [.session: ["alice.0": Data([1])]])
		let store = CacheableSignalKeyStore(store: backing, ttl: 10, now: clock.now)

		_ = try await store.get(.session, ids: ["alice.0"])
		await backing.update(.session, id: "alice.0", value: Data([2]))
		#expect(try await store.get(.session, ids: ["alice.0"]) == ["alice.0": Data([1])])

		clock.advance(by: 11)

		#expect(try await store.get(.session, ids: ["alice.0"]) == ["alice.0": Data([2])])
		#expect(await backing.getRequests == [
			SignalKeyStoreGetRequest(category: .session, ids: ["alice.0"]),
			SignalKeyStoreGetRequest(category: .session, ids: ["alice.0"])
		])
	}

	@Test("authentication state uses cacheable file-backed signal keys")
	func authenticationStateUsesCacheableFileBackedSignalKeys() async throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("swift-baileys-auth-\(UUID().uuidString)", isDirectory: true)
		let store = FileAuthenticationStore(directory: directory)
		let state = try await AuthenticationState.loadOrCreate(
			store: store,
			credentialsFactory: sampleCredentials
		)

		try await state.keys.set([.session: ["alice.0": Data([1])]])

		#expect(try await state.keys.get(.session, ids: ["alice.0"]) == ["alice.0": Data([1])])
		#expect(try await store.keys.get(.session, ids: ["alice.0"]) == ["alice.0": Data([1])])
		#expect(state.transactionalKeys != nil)
	}

	@Test("transactional key store commits staged writes on success")
	func transactionalKeyStoreCommitsStagedWritesOnSuccess() async throws {
		let backing = CountingSignalKeyStore()
		let store = TransactionalSignalKeyStore(store: backing)

		let value = try await store.transaction(key: "session") { transaction in
			try await transaction.set([.session: ["alice.0": Data([1])]])
			return try await transaction.get(.session, ids: ["alice.0"])
		}

		#expect(value == ["alice.0": Data([1])])
		#expect(try await backing.get(.session, ids: ["alice.0"]) == ["alice.0": Data([1])])
	}

	@Test("transactional key store rolls back staged writes on failure")
	func transactionalKeyStoreRollsBackStagedWritesOnFailure() async throws {
		let backing = CountingSignalKeyStore()
		let store = TransactionalSignalKeyStore(store: backing)

		await #expect(throws: AuthStoreTestError.transactionFailed) {
			try await store.transaction(key: "session") { transaction in
				try await transaction.set([.session: ["alice.0": Data([1])]])
				throw AuthStoreTestError.transactionFailed
			}
		}

		let stored = try await backing.get(.session, ids: ["alice.0"])
		#expect(stored.isEmpty)
	}

	@Test("transactional key store retries failed commits")
	func transactionalKeyStoreRetriesFailedCommits() async throws {
		let backing = CountingSignalKeyStore(failSetAttempts: 1)
		let store = TransactionalSignalKeyStore(
			store: backing,
			options: SignalKeyTransactionOptions(maxCommitRetries: 2, delayBetweenRetries: .zero)
		)

		try await store.transaction(key: "session") { transaction in
			try await transaction.set([.session: ["alice.0": Data([1])]])
		}

		#expect(await backing.setAttempts == 2)
		#expect(try await backing.get(.session, ids: ["alice.0"]) == ["alice.0": Data([1])])
	}

	@Test("transactional key store stages clear until commit")
	func transactionalKeyStoreStagesClearUntilCommit() async throws {
		let backing = CountingSignalKeyStore(storage: [.session: ["alice.0": Data([1])]])
		let store = TransactionalSignalKeyStore(store: backing)

		try await store.transaction(key: "session") { transaction in
			try await transaction.clear()
			#expect(try await transaction.get(.session, ids: ["alice.0"]).isEmpty)
		}

		#expect(try await backing.get(.session, ids: ["alice.0"]).isEmpty)
	}

	@Test("file auth store restricts directory and key file permissions")
	func fileAuthStoreRestrictsDirectoryAndKeyFilePermissions() async throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("swift-baileys-auth-\(UUID().uuidString)", isDirectory: true)
		let store = FileAuthenticationStore(directory: directory)

		try await store.saveCredentials(sampleCredentials())
		try await store.keys.set([.session: ["user/phone:0": Data([1])]])

		#expect(try posixPermissions(at: directory) == 0o700)
		#expect(try posixPermissions(at: directory.appendingPathComponent("creds.json")) == 0o600)
		#expect(try posixPermissions(at: directory.appendingPathComponent("session-dXNlci9waG9uZTow.json")) == 0o600)
	}

	@Test("file auth store keeps colliding legacy key ids distinct")
	func fileAuthStoreKeepsCollidingLegacyKeyIDsDistinct() async throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("swift-baileys-auth-\(UUID().uuidString)", isDirectory: true)
		let store = FileAuthenticationStore(directory: directory)

		try await store.keys.set([
			.session: [
				"user/phone:0": Data([1]),
				"user__phone-0": Data([2])
			]
		])

		#expect(try await store.keys.get(.session, ids: ["user/phone:0", "user__phone-0"]) == [
			"user/phone:0": Data([1]),
			"user__phone-0": Data([2])
		])
	}

	@Test("file auth store reads and removes legacy key files")
	func fileAuthStoreReadsAndRemovesLegacyKeyFiles() async throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("swift-baileys-auth-\(UUID().uuidString)", isDirectory: true)
		let store = FileAuthenticationStore(directory: directory)
		let legacyURL = directory.appendingPathComponent("session-user__phone-0.json")

		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		try JSONEncoder().encode(Data([3])).write(to: legacyURL, options: .atomic)

		#expect(try await store.keys.get(.session, ids: ["user/phone:0"]) == ["user/phone:0": Data([3])])

		try await store.keys.set([.session: ["user/phone:0": nil]])

		#expect(try await store.keys.get(.session, ids: ["user/phone:0"]).isEmpty)
		#expect(!FileManager.default.fileExists(atPath: legacyURL.path))
	}

	@Test("file auth store reads credentials written with Baileys BufferJSON")
	func fileAuthStoreReadsCredentialsWrittenWithBaileysBufferJSON() async throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("swift-baileys-auth-\(UUID().uuidString)", isDirectory: true)
		let store = FileAuthenticationStore(directory: directory)
		let credentialsURL = directory.appendingPathComponent("creds.json")
		let json = """
		{
			"noiseKey": {
				"privateKey": { "type": "Buffer", "data": "AQ==" },
				"publicKey": { "type": "Buffer", "data": "Ag==" }
			},
			"pairingEphemeralKeyPair": {
				"privateKey": { "type": "Buffer", "data": "Aw==" },
				"publicKey": { "type": "Buffer", "data": "BA==" }
			},
			"signedIdentityKey": {
				"privateKey": { "type": "Buffer", "data": "BQ==" },
				"publicKey": { "type": "Buffer", "data": "Bg==" }
			},
			"signedPreKey": {
				"keyPair": {
					"privateKey": { "type": "Buffer", "data": "Bw==" },
					"publicKey": { "type": "Buffer", "data": "CA==" }
				},
				"signature": { "type": "Buffer", "data": "CQ==" },
				"keyID": 1
			},
			"registrationID": 123,
			"advSecretKey": "adv-secret",
			"signalIdentities": [],
			"nextPreKeyID": 1,
			"firstUnuploadedPreKeyID": 1,
			"accountSyncCounter": 0,
			"accountSettings": { "unarchiveChats": false },
			"registered": false,
			"processedHistoryMessages": []
		}
		"""

		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		try Data(json.utf8).write(to: credentialsURL, options: .atomic)

		#expect(try await store.loadCredentials() == sampleCredentials())
	}

	@Test("file auth store removes keys when nil is written")
	func fileAuthStoreRemovesKeysWhenNilIsWritten() async throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("swift-baileys-auth-\(UUID().uuidString)", isDirectory: true)
		let store = FileAuthenticationStore(directory: directory)

		try await store.keys.set([.preKey: ["1": Data([1])]])
		try await store.keys.set([.preKey: ["1": nil]])

		#expect(try await store.keys.get(.preKey, ids: ["1"]).isEmpty)
		#expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("pre-key-1.json").path))
	}

	private func sampleCredentials() -> AuthenticationCredentials {
		AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data([6])),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([8])),
				signature: Data([9]),
				keyID: 1
			),
			registrationID: 123,
			advSecretKey: "adv-secret",
			nextPreKeyID: 1,
			firstUnuploadedPreKeyID: 1,
			accountSyncCounter: 0,
			registered: false
		)
	}

	private func posixPermissions(at url: URL) throws -> Int {
		let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
		return try #require(attributes[.posixPermissions] as? Int) & 0o777
	}
}

private actor CountingSignalKeyStore: SignalKeyStore {
	private var storage: [SignalKeyCategory: [String: Data]]
	private var requests: [SignalKeyStoreGetRequest] = []
	private var setCount = 0
	private var remainingFailedSetAttempts: Int

	init(storage: [SignalKeyCategory: [String: Data]] = [:], failSetAttempts: Int = 0) {
		self.storage = storage
		self.remainingFailedSetAttempts = failSetAttempts
	}

	var getRequests: [SignalKeyStoreGetRequest] {
		requests
	}

	var setAttempts: Int {
		setCount
	}

	func get(_ category: SignalKeyCategory, ids: [String]) async throws -> [String: Data] {
		requests.append(SignalKeyStoreGetRequest(category: category, ids: ids))
		let values = storage[category] ?? [:]
		return ids.reduce(into: [:]) { result, id in
			if let value = values[id] {
				result[id] = value
			}
		}
	}

	func set(_ values: [SignalKeyCategory: [String: Data?]]) async throws {
		setCount += 1
		if remainingFailedSetAttempts > 0 {
			remainingFailedSetAttempts -= 1
			throw AuthStoreTestError.commitFailed
		}

		for (category, updates) in values {
			for (id, value) in updates {
				update(category, id: id, value: value)
			}
		}
	}

	func clear() async throws {
		storage.removeAll()
	}

	func update(_ category: SignalKeyCategory, id: String, value: Data?) {
		if let value {
			var values = storage[category] ?? [:]
			values[id] = value
			storage[category] = values
		} else {
			storage[category]?.removeValue(forKey: id)
		}
	}
}

private enum AuthStoreTestError: Error, Equatable {
	case transactionFailed
	case commitFailed
}

private struct SignalKeyStoreGetRequest: Equatable {
	let category: SignalKeyCategory
	let ids: [String]
}

private final class MutableClock: @unchecked Sendable {
	private let lock = NSLock()
	private var date: Date

	init(date: Date) {
		self.date = date
	}

	func now() -> Date {
		lock.withLock { date }
	}

	func advance(by seconds: TimeInterval) {
		lock.withLock {
			date = date.addingTimeInterval(seconds)
		}
	}
}
