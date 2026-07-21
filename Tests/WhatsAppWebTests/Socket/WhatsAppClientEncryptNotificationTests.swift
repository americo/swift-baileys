import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client encrypt notifications")
struct WhatsAppClientEncryptNotificationTests {
	@Test("queries available pre-key count on server")
	func queriesAvailablePreKeyCountOnServer() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.getAvailablePreKeysOnServer(requestID: "pre-key-count")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "pre-key-count")
		#expect(request.attrs["xmlns"] == "encrypt")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.firstChild(named: "count") != nil)

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "pre-key-count", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "count", attrs: ["value": "17"])
			])
		))

		#expect(try await task.value == 17)
	}

	@Test("throws when available pre-key count response is missing count")
	func throwsWhenAvailablePreKeyCountResponseIsMissingCount() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.getAvailablePreKeysOnServer(requestID: "pre-key-count-missing")
		}
		_ = try await transport.waitForSentNode()
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "pre-key-count-missing", "type": "result"]
		))

		await #expect(throws: PreKeyCountQueryError.missingCount) {
			try await task.value
		}
	}

	@Test("uploads more pre-keys when server count is low")
	func uploadsMorePreKeysWhenServerCountIsLow() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let uploader = StubPreKeyUploader()
		let client = WhatsAppClient(transportFactory: { _ in transport }, preKeyUploader: uploader)
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "encrypt-1", "type": "encrypt"],
			content: .nodes([
				BinaryNode(tag: "count", attrs: ["value": "3"])
			])
		))

		#expect(await events.next() == .preKeyCountUpdated(PreKeyCountUpdate(
			count: 3,
			shouldUploadMorePreKeys: true
		)))
		#expect(await uploader.calls == [5])
		let ack = try await firstEncryptNotificationAck(from: transport)
		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: ["id": "encrypt-1", "to": "@s.whatsapp.net", "class": "notification", "type": "encrypt"]
		))
	}

	@Test("emits pre-key upload failures when low-count recovery fails")
	func emitsPreKeyUploadFailuresWhenLowCountRecoveryFails() async throws {
		let uploader = StubPreKeyUploader(error: StubPreKeyUploadError.failed)
		let client = WhatsAppClient(preKeyUploader: uploader)
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "encrypt-fail", "type": "encrypt"],
			content: .nodes([
				BinaryNode(tag: "count", attrs: ["value": "2"])
			])
		))

		#expect(await events.next() == .preKeyCountUpdated(PreKeyCountUpdate(
			count: 2,
			shouldUploadMorePreKeys: true
		)))
		#expect(await events.next() == .preKeyUploadFailed(PreKeyUploadFailure(
			currentCount: 2,
			requestedUploadCount: 5,
			reason: "failed"
		)))
		#expect(await uploader.calls == [5])
	}

	@Test("emits typed pre-key upload failures when default upload lacks auth state")
	func emitsTypedPreKeyUploadFailuresWhenDefaultUploadLacksAuthState() async throws {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "encrypt-auth-fail", "type": "encrypt"],
			content: .nodes([
				BinaryNode(tag: "count", attrs: ["value": "1"])
			])
		))

		#expect(await events.next() == .preKeyCountUpdated(PreKeyCountUpdate(
			count: 1,
			shouldUploadMorePreKeys: true
		)))
		#expect(await events.next() == .preKeyUploadFailed(PreKeyUploadFailure(
			currentCount: 1,
			requestedUploadCount: 5,
			reason: "missingAuthenticationState",
			failureReason: .missingAuthenticationState
		)))
	}

	@Test("builds uploads and persists generated pre-keys")
	func buildsUploadsAndPersistsGeneratedPreKeys() async throws {
		let transport = MockProfileWebSocketTransport()
		let keyStore = InMemorySignalKeyStore()
		let keyGenerator = DeterministicPreKeyGenerator(keys: [
			AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32)),
			AuthenticationKeyPair(privateKey: Data(repeating: 3, count: 32), publicKey: Data(repeating: 4, count: 32))
		])
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePreKeyUploadCredentials(),
				keys: keyStore
			),
			transportFactory: { _ in transport },
			messageIDGenerator: MessageIDGenerator(
				unixTimestampSeconds: { 1 },
				randomBytes: { Data(repeating: 0x22, count: $0) }
			),
			preKeyGenerator: { try awaitlessKeyPair(from: keyGenerator) }
		)
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		let upload = Task {
			try await client.uploadPreKeys(count: 2)
		}
		let request = try await transport.waitForSentNode()
		let id = try #require(request.attrs["id"])
		await client.handleIncomingNode(BinaryNode(tag: "iq", attrs: ["id": id, "type": "result"]))
		try await upload.value

		#expect(request.attrs["xmlns"] == "encrypt")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.childData(named: "registration") == Data([0, 0, 2, 47]))
		#expect(request.childData(named: "type") == Data([5]))
		#expect(request.childData(named: "identity") == Data(repeating: 9, count: 32))
		let keys = try #require(request.firstChild(named: "list")?.children(named: "key"))
		#expect(keys.map { $0.childData(named: "id") } == [Data([0, 0, 7]), Data([0, 0, 8])])
		#expect(keys.map { $0.childData(named: "value") } == [Data(repeating: 2, count: 32), Data(repeating: 4, count: 32)])
		let signedPreKey = try #require(request.firstChild(named: "skey"))
		#expect(signedPreKey.childData(named: "id") == Data([0, 0, 1]))
		#expect(signedPreKey.childData(named: "value") == Data(repeating: 8, count: 32))
		#expect(signedPreKey.childData(named: "signature") == Data(repeating: 7, count: 64))

		let stored = try await keyStore.get(.preKey, ids: ["7", "8"])
		#expect(try JSONDecoder().decode(StoredPreKey.self, from: try #require(stored["7"])) == StoredPreKey(
			privateKey: Data(repeating: 1, count: 32),
			publicKey: Data(repeating: 2, count: 32)
		))
		#expect(try JSONDecoder().decode(StoredPreKey.self, from: try #require(stored["8"])) == StoredPreKey(
			privateKey: Data(repeating: 3, count: 32),
			publicKey: Data(repeating: 4, count: 32)
		))
		let updated = try #require(await client.authenticationState?.credentials)
		#expect(updated.nextPreKeyID == 9)
		#expect(updated.firstUnuploadedPreKeyID == 9)
		#expect(await events.next() == .credentialsUpdated(updated))
	}

	@Test("rejects non-positive default pre-key upload counts")
	func rejectsNonPositiveDefaultPreKeyUploadCounts() async throws {
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: samplePreKeyUploadCredentials(),
			keys: InMemorySignalKeyStore()
		))

		await #expect(throws: PreKeyUploadRequestError.invalidRequestedUploadCount) {
			try await client.uploadPreKeys(count: 0)
		}
		await #expect(throws: PreKeyUploadRequestError.invalidRequestedUploadCount) {
			try await client.uploadPreKeys(count: -1)
		}
	}

	@Test("rejects generated pre-keys with invalid Curve25519 material")
	func rejectsGeneratedPreKeysWithInvalidCurve25519Material() async throws {
		let keyStore = InMemorySignalKeyStore()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePreKeyUploadCredentials(),
				keys: keyStore
			),
			preKeyGenerator: {
				AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 31), publicKey: Data(repeating: 2, count: 32))
			}
		)

		await #expect(throws: PreKeyUploadRequestError.invalidKeyMaterial) {
			try await client.uploadPreKeys(count: 1)
		}
		#expect(try await keyStore.get(.preKey, ids: ["7"]).isEmpty)
		let credentials = try #require(await client.authenticationState?.credentials)
		#expect(credentials.nextPreKeyID == 7)
		#expect(credentials.firstUnuploadedPreKeyID == 7)
	}

	@Test("rejects invalid generated pre-key IDs before default pre-key upload")
	func rejectsInvalidGeneratedPreKeyIDsBeforeDefaultPreKeyUpload() async throws {
		let keyStore = InMemorySignalKeyStore()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePreKeyUploadCredentials(firstUnuploadedPreKeyID: 0),
				keys: keyStore
			),
			preKeyGenerator: {
				AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32))
			}
		)

		await #expect(throws: PreKeyUploadRequestError.invalidKeyID) {
			try await client.uploadPreKeys(count: 1)
		}
		#expect(try await keyStore.get(.preKey, ids: ["0"]).isEmpty)
		let credentials = try #require(await client.authenticationState?.credentials)
		#expect(credentials.nextPreKeyID == 7)
		#expect(credentials.firstUnuploadedPreKeyID == 0)
	}

	@Test("rejects invalid signed pre-key material before default pre-key upload")
	func rejectsInvalidSignedPreKeyMaterialBeforeDefaultPreKeyUpload() async throws {
		let keyStore = InMemorySignalKeyStore()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePreKeyUploadCredentials(signedPreKeySignature: Data([7, 7])),
				keys: keyStore
			),
			preKeyGenerator: {
				AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32))
			}
		)

		await #expect(throws: PreKeyUploadRequestError.invalidKeyMaterial) {
			try await client.uploadPreKeys(count: 1)
		}
		#expect(try await keyStore.get(.preKey, ids: ["7"]).isEmpty)
		let credentials = try #require(await client.authenticationState?.credentials)
		#expect(credentials.nextPreKeyID == 7)
		#expect(credentials.firstUnuploadedPreKeyID == 7)
	}

	@Test("rejects invalid signed pre-key public key before default pre-key upload")
	func rejectsInvalidSignedPreKeyPublicKeyBeforeDefaultPreKeyUpload() async throws {
		let keyStore = InMemorySignalKeyStore()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePreKeyUploadCredentials(signedPreKeyPublicKey: Data([8, 8])),
				keys: keyStore
			),
			preKeyGenerator: {
				AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32))
			}
		)

		await #expect(throws: PreKeyUploadRequestError.invalidKeyMaterial) {
			try await client.uploadPreKeys(count: 1)
		}
		#expect(try await keyStore.get(.preKey, ids: ["7"]).isEmpty)
		let credentials = try #require(await client.authenticationState?.credentials)
		#expect(credentials.nextPreKeyID == 7)
		#expect(credentials.firstUnuploadedPreKeyID == 7)
	}

	@Test("rejects invalid signed pre-key ID before default pre-key upload")
	func rejectsInvalidSignedPreKeyIDBeforeDefaultPreKeyUpload() async throws {
		let keyStore = InMemorySignalKeyStore()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePreKeyUploadCredentials(signedPreKeyID: 0),
				keys: keyStore
			),
			preKeyGenerator: {
				AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32))
			}
		)

		await #expect(throws: PreKeyUploadRequestError.invalidKeyID) {
			try await client.uploadPreKeys(count: 1)
		}
		#expect(try await keyStore.get(.preKey, ids: ["7"]).isEmpty)
		let credentials = try #require(await client.authenticationState?.credentials)
		#expect(credentials.nextPreKeyID == 7)
		#expect(credentials.firstUnuploadedPreKeyID == 7)
	}

	@Test("rejects invalid identity key material before default pre-key upload")
	func rejectsInvalidIdentityKeyMaterialBeforeDefaultPreKeyUpload() async throws {
		let keyStore = InMemorySignalKeyStore()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePreKeyUploadCredentials(identityPublicKey: Data([9, 9])),
				keys: keyStore
			),
			preKeyGenerator: {
				AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32))
			}
		)

		await #expect(throws: PreKeyUploadRequestError.invalidKeyMaterial) {
			try await client.uploadPreKeys(count: 1)
		}
		#expect(try await keyStore.get(.preKey, ids: ["7"]).isEmpty)
		let credentials = try #require(await client.authenticationState?.credentials)
		#expect(credentials.nextPreKeyID == 7)
		#expect(credentials.firstUnuploadedPreKeyID == 7)
	}

	@Test("coalesces concurrent pre-key uploads")
	func coalescesConcurrentPreKeyUploads() async throws {
		let transport = MockProfileWebSocketTransport()
		let keyStore = InMemorySignalKeyStore()
		let keyGenerator = DeterministicPreKeyGenerator(keys: [
			AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32)),
			AuthenticationKeyPair(privateKey: Data(repeating: 3, count: 32), publicKey: Data(repeating: 4, count: 32)),
			AuthenticationKeyPair(privateKey: Data(repeating: 5, count: 32), publicKey: Data(repeating: 6, count: 32)),
			AuthenticationKeyPair(privateKey: Data(repeating: 7, count: 32), publicKey: Data(repeating: 8, count: 32))
		])
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePreKeyUploadCredentials(),
				keys: keyStore
			),
			transportFactory: { _ in transport },
			messageIDGenerator: MessageIDGenerator(
				unixTimestampSeconds: { 1 },
				randomBytes: { Data(repeating: 0x22, count: $0) }
			),
			preKeyGenerator: { try awaitlessKeyPair(from: keyGenerator) }
		)
		try await client.connect()

		let firstUpload = Task { try await client.uploadPreKeys(count: 2) }
		let secondUpload = Task { try await client.uploadPreKeys(count: 2) }
		_ = try await transport.waitForSentNode()
		try await Task.sleep(for: .milliseconds(20))
		let sentCount = await transport.sentFrameCount()

		#expect(sentCount == 1)
		for index in 0..<sentCount {
			let request = try await transport.waitForSentNode(at: index)
			let id = try #require(request.attrs["id"])
			await client.handleIncomingNode(BinaryNode(tag: "iq", attrs: ["id": id, "type": "result"]))
		}

		try await firstUpload.value
		try await secondUpload.value

		let stored = try await keyStore.get(.preKey, ids: ["7", "8", "9", "10"])
		#expect(stored.keys.sorted() == ["7", "8"])
		let updated = try #require(await client.authenticationState?.credentials)
		#expect(updated.nextPreKeyID == 9)
		#expect(updated.firstUnuploadedPreKeyID == 9)
	}

	@Test("refreshes sessions for primary identity-change notifications")
	func refreshesSessionsForPrimaryIdentityChangeNotifications() async throws {
		let sessionPreparer = StubEncryptSessionPreparer()
		let client = WhatsAppClient(signalSessionPreparer: sessionPreparer)
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "123@s.whatsapp.net", "id": "encrypt-2", "type": "encrypt"],
			content: .nodes([
				BinaryNode(tag: "identity")
			])
		))

		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123@s.whatsapp.net"], force: true)
		])
		#expect(await events.next() == .identityChanged(IdentityChangeUpdate(
			jid: "123@s.whatsapp.net",
			action: .sessionRefreshRequested
		)))
	}

	@Test("reissues trusted contact token when primary identity changes")
	func reissuesTrustedContactTokenWhenPrimaryIdentityChanges() async throws {
		let transport = MockProfileWebSocketTransport()
		let sessionPreparer = StubEncryptSessionPreparer()
		let senderTimestamp = String(Int(Date().timeIntervalSince1970))
		let keys = InMemorySignalKeyStore(storage: [
			.tcToken: [
				"123@s.whatsapp.net": try TrustedContactTokenCoding.encode(TrustedContactToken(
					token: Data(),
					timestamp: "1",
					senderTimestamp: senderTimestamp
				))
			]
		])
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: samplePreKeyUploadCredentials(), keys: keys),
			transportFactory: { _ in transport },
			signalSessionPreparer: sessionPreparer
		)
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "123@s.whatsapp.net", "id": "encrypt-reissue", "type": "encrypt"],
			content: .nodes([
				BinaryNode(tag: "identity")
			])
		))

		try await Task.sleep(for: .milliseconds(25))
		let sentCount = await transport.sentFrameCount()
		var privacyRequests: [BinaryNode] = []
		for index in 0..<sentCount {
			let node = try await transport.waitForSentNode(at: index)
			if node.attrs["xmlns"] == "privacy" {
				privacyRequests.append(node)
			}
		}

		let request = try #require(privacyRequests.first)
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "privacy")
		let token = try #require(request.firstChild(named: "tokens")?.firstChild(named: "token"))
		#expect(token.attrs["jid"] == "123@s.whatsapp.net")
		#expect(token.attrs["t"] == senderTimestamp)
		#expect(token.attrs["type"] == "trusted_contact")
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": try #require(request.attrs["id"]), "type": "result"]
		))
	}

	@Test("uses Baileys string presence semantics for offline identity-change notifications")
	func usesBaileysStringPresenceSemanticsForOfflineIdentityChangeNotifications() async {
		let onlinePreparer = StubEncryptSessionPreparer()
		let onlineClient = WhatsAppClient(signalSessionPreparer: onlinePreparer)
		var onlineEvents = onlineClient.events.makeAsyncIterator()
		await onlineClient.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "123@s.whatsapp.net", "id": "encrypt-online", "type": "encrypt", "offline": ""],
			content: .nodes([BinaryNode(tag: "identity")])
		))
		#expect(await onlinePreparer.calls == [SignalSessionPreparationCall(jids: ["123@s.whatsapp.net"], force: true)])
		#expect(await onlineEvents.next() == .identityChanged(IdentityChangeUpdate(jid: "123@s.whatsapp.net", action: .sessionRefreshRequested)))

		let offlinePreparer = StubEncryptSessionPreparer()
		let offlineClient = WhatsAppClient(signalSessionPreparer: offlinePreparer)
		var offlineEvents = offlineClient.events.makeAsyncIterator()
		await offlineClient.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "123@s.whatsapp.net", "id": "encrypt-offline", "type": "encrypt", "offline": "1"],
			content: .nodes([BinaryNode(tag: "identity")])
		))
		#expect(await offlinePreparer.calls.isEmpty)
		#expect(await offlineEvents.next() == .identityChanged(IdentityChangeUpdate(jid: "123@s.whatsapp.net", action: .skippedOffline)))
	}

	@Test("skips identity-change session refresh for companion device notifications")
	func skipsIdentityChangeRefreshForCompanionDeviceNotifications() async {
		let sessionPreparer = StubEncryptSessionPreparer()
		let client = WhatsAppClient(signalSessionPreparer: sessionPreparer)
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "123:4@s.whatsapp.net", "id": "encrypt-3", "type": "encrypt"],
			content: .nodes([
				BinaryNode(tag: "identity")
			])
		))

		#expect(await sessionPreparer.calls.isEmpty)
		#expect(await events.next() == .identityChanged(IdentityChangeUpdate(
			jid: "123:4@s.whatsapp.net",
			action: .skippedCompanionDevice
		)))
	}
}

private actor StubPreKeyUploader: PreKeyUploading {
	private let error: (any Error)?
	private(set) var calls: [Int] = []

	init(error: (any Error)? = nil) {
		self.error = error
	}

	func uploadPreKeys(count: Int) async throws {
		calls.append(count)
		if let error {
			throw error
		}
	}
}

private enum StubPreKeyUploadError: Error, CustomStringConvertible {
	case failed

	var description: String {
		"failed"
	}
}

private final class DeterministicPreKeyGenerator: @unchecked Sendable {
	private let lock = NSLock()
	private var keys: [AuthenticationKeyPair]

	init(keys: [AuthenticationKeyPair]) {
		self.keys = keys
	}

	func next() throws -> AuthenticationKeyPair {
		lock.lock()
		defer { lock.unlock() }
		return keys.removeFirst()
	}
}

private func awaitlessKeyPair(from generator: DeterministicPreKeyGenerator) throws -> AuthenticationKeyPair {
	try generator.next()
}

private func samplePreKeyUploadCredentials(
	identityPublicKey: Data = Data([5]) + Data(repeating: 9, count: 32),
	signedPreKeyPublicKey: Data = Data([5]) + Data(repeating: 8, count: 32),
	signedPreKeySignature: Data = Data(repeating: 7, count: 64),
	signedPreKeyID: Int = 1,
	firstUnuploadedPreKeyID: Int = 7
) -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
		signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: identityPublicKey),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(privateKey: Data([6]), publicKey: signedPreKeyPublicKey),
			signature: signedPreKeySignature,
			keyID: signedPreKeyID
		),
		registrationID: 559,
		advSecretKey: "adv-secret",
		me: WhatsAppUser(id: "258840000000@s.whatsapp.net"),
		nextPreKeyID: 7,
		firstUnuploadedPreKeyID: firstUnuploadedPreKeyID,
		accountSyncCounter: 0,
		registered: true
	)
}

private actor StubEncryptSessionPreparer: SignalSessionPreparing {
	private(set) var calls: [SignalSessionPreparationCall] = []

	func assertSessions(for jids: [String], force: Bool) async throws -> Bool {
		calls.append(SignalSessionPreparationCall(jids: jids, force: force))
		return true
	}
}

private func firstEncryptNotificationAck(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	let frame = try #require(await transport.sentFrames.first)
	var codec = NoiseFrameCodec()
	return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
}
