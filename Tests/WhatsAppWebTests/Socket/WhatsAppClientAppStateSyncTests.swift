import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client app-state sync")
struct WhatsAppClientAppStateSyncTests {
	@Test("stores app-state sync keys from received key share")
	func storesAppStateSyncKeysFromReceivedKeyShare() async throws {
		let keys = InMemorySignalKeyStore()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: appStateCredentials(), keys: keys)
		)

		try await client.storeAppStateSyncKeys(ReceivedAppStateSyncKeyShareContent(keys: [
			ReceivedAppStateSyncKeyContent(
				keyID: Data([1, 2, 3]),
				keyIDBase64: nil,
				keyData: Data((0..<32).map(UInt8.init)),
				fingerprint: ReceivedAppStateSyncKeyFingerprintContent(
					rawID: 7,
					currentIndex: 2,
					deviceIndexes: [1, 3, 5]
				),
				timestamp: 1234
			),
			ReceivedAppStateSyncKeyContent(
				keyID: Data([4, 5, 6]),
				keyIDBase64: nil,
				keyData: nil,
				fingerprint: nil,
				timestamp: nil
			)
		]))

		let stored = try await keys.get(.appStateSyncKey, ids: ["AQID", "BAUG"])
		let keyData = try Proto_Message.AppStateSyncKeyData(serializedBytes: try #require(stored["AQID"]))
		#expect(keyData.keyData == Data((0..<32).map(UInt8.init)))
		#expect(keyData.timestamp == 1234)
		#expect(keyData.fingerprint.rawID == 7)
		#expect(keyData.fingerprint.currentIndex == 2)
		#expect(keyData.fingerprint.deviceIndexes == [1, 3, 5])
		#expect(stored["BAUG"] == nil)
	}

	@Test("requests sync from stored collection versions")
	func requestsSyncFromStoredCollectionVersions() async throws {
		let keys = InMemorySignalKeyStore(storage: [
			.appStateSyncVersion: [
				"regular_low": try JSONEncoder().encode(AppStatePatchState(version: 4, hash: Data(repeating: 6, count: 128)))
			]
		])
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: appStateCredentials(), keys: keys),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let task = Task {
			try await client.requestAppStateSync(
				collections: [AppStateCollectionName.regularLow, .criticalBlock],
				requestID: "app-sync-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "app-sync-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "w:sync:app:state")
		let collections = try #require(request.firstChild(named: "sync")?.children(named: "collection"))
		#expect(collections.map { $0.attrs["name"] } == ["regular_low", "critical_block"])
		#expect(collections.map { $0.attrs["version"] } == ["4", "0"])
		#expect(collections.map { $0.attrs["return_snapshot"] } == ["false", "true"])

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "app-sync-1", "type": "result"]))
		_ = try await task.value
	}

	@Test("force snapshot requests snapshots for stored collections")
	func forceSnapshotRequestsSnapshotsForStoredCollections() async throws {
		let keys = InMemorySignalKeyStore(storage: [
			.appStateSyncVersion: [
				"regular": try JSONEncoder().encode(AppStatePatchState(version: 8, hash: Data(repeating: 7, count: 128)))
			]
		])
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: appStateCredentials(), keys: keys),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let task = Task {
			try await client.requestAppStateSync(
				collections: [AppStateCollectionName.regular],
				forceSnapshot: true,
				requestID: "app-sync-force"
			)
		}
		let request = try await transport.waitForSentNode()
		let collection = try #require(request.firstChild(named: "sync")?.firstChild(named: "collection"))
		#expect(collection.attrs["name"] == "regular")
		#expect(collection.attrs["version"] == "8")
		#expect(collection.attrs["return_snapshot"] == "true")

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "app-sync-force", "type": "result"]))
		_ = try await task.value
	}

	@Test("sync app state decodes server patches and persists collection state")
	func syncAppStateDecodesServerPatchesAndPersistsCollectionState() async throws {
		var appStateKeyData = Proto_Message.AppStateSyncKeyData()
		appStateKeyData.keyData = Data((0..<32).map(UInt8.init))
		let keys = InMemorySignalKeyStore(storage: [
			.appStateSyncKey: ["AQIDBAUGBwg=": try appStateKeyData.serializedData()]
		])
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: appStateCredentials(), keys: keys),
			transportFactory: { _ in transport }
		)
		let encoded = try AppStatePatchEncoder.encode(
			ChatModificationPatchBuilder.patch(for: .pin(jid: "123@s.whatsapp.net", pinned: true)),
			keyID: try appStateHexData("0102030405060708"),
			keys: try appStateFixtureKeys(),
			state: AppStatePatchState(),
			iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)
		var patch = encoded.patch
		patch.version.version = encoded.state.version
		try await client.connect()

		let task = Task {
			try await client.syncAppState(collections: [.regularLow])
		}
		let request = try await transport.waitForSentNode()
		let collectionRequest = try #require(request.firstChild(named: "sync")?.firstChild(named: "collection"))
		#expect(collectionRequest.attrs["name"] == "regular_low")
		#expect(collectionRequest.attrs["version"] == "0")
		#expect(collectionRequest.attrs["return_snapshot"] == "true")
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": try #require(request.attrs["id"]), "type": "result"],
			content: .nodes([
				BinaryNode(tag: "sync", content: .nodes([
					BinaryNode(
						tag: "collection",
						attrs: ["name": "regular_low", "version": "0", "has_more_patches": "false"],
						content: .nodes([
							BinaryNode(tag: "patch", content: .data(try patch.serializedData()))
						])
					)
				]))
			])
		))

		let result = try await task.value
		#expect(result.collectionVersions == ["regular_low": 1])
		#expect(result.hasMorePatches == ["regular_low": false])
		#expect(result.decodedMutationCount == 1)
		let stored = try await keys.get(.appStateSyncVersion, ids: ["regular_low"])
		let storedState = try JSONDecoder().decode(AppStatePatchState.self, from: try #require(stored["regular_low"]))
		#expect(storedState == encoded.state)
	}

	@Test("sync app state downloads external patch blobs through media downloader")
	func syncAppStateDownloadsExternalPatchBlobsThroughMediaDownloader() async throws {
		var appStateKeyData = Proto_Message.AppStateSyncKeyData()
		appStateKeyData.keyData = Data((0..<32).map(UInt8.init))
		let keys = InMemorySignalKeyStore(storage: [
			.appStateSyncKey: ["AQIDBAUGBwg=": try appStateKeyData.serializedData()]
		])
		let encoded = try AppStatePatchEncoder.encode(
			ChatModificationPatchBuilder.patch(for: .pin(jid: "123@s.whatsapp.net", pinned: true)),
			keyID: try appStateHexData("0102030405060708"),
			keys: try appStateFixtureKeys(),
			state: AppStatePatchState(),
			iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)
		var externalMutations = Proto_SyncdMutations()
		externalMutations.mutations = encoded.patch.mutations
		let mediaKey = Data((32..<64).map(UInt8.init))
		let encryptedBlob = try MediaEncryption.encrypt(
			try externalMutations.serializedData(),
			mediaKey: mediaKey,
			mediaType: .mdAppState
		)
		var blob = Proto_ExternalBlobReference()
		blob.mediaKey = mediaKey
		blob.directPath = "/mms/md-app-state/external-patch"
		blob.fileSha256 = encryptedBlob.fileSha256
		blob.fileEncSha256 = encryptedBlob.fileEncSha256
		blob.fileSizeBytes = UInt64(encryptedBlob.encryptedFile.count)
		var patch = encoded.patch
		patch.version.version = encoded.state.version
		patch.mutations = []
		patch.externalMutations = blob
		let blobTransport = StubAppStateBlobTransport(data: encryptedBlob.encryptedFile)
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: appStateCredentials(), keys: keys),
			transportFactory: { _ in transport },
			mediaDownloader: WhatsAppMediaDownloader(transport: blobTransport)
		)
		try await client.connect()

		let task = Task {
			try await client.syncAppState(collections: [.regularLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueAppStatePatchResponse(
			patch,
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		let result = try await task.value
		#expect(result.collectionVersions == ["regular_low": 1])
		#expect(result.decodedMutationCount == 1)
		#expect(await blobTransport.urls == [
			URL(string: "https://mmg.whatsapp.net/mms/md-app-state/external-patch")!
		])
	}

	@Test("received app-state keys retry blocked sync collections")
	func receivedAppStateKeysRetryBlockedSyncCollections() async throws {
		let keys = InMemorySignalKeyStore()
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: appStateCredentials(), keys: keys),
			transportFactory: { _ in transport }
		)
		let encoded = try AppStatePatchEncoder.encode(
			ChatModificationPatchBuilder.patch(for: .pin(jid: "123@s.whatsapp.net", pinned: true)),
			keyID: try appStateHexData("0102030405060708"),
			keys: try appStateFixtureKeys(),
			state: AppStatePatchState(),
			iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)
		var patch = encoded.patch
		patch.version.version = encoded.state.version
		try await client.connect()

		let blockedTask = Task {
			try await client.syncAppState(collections: [.regularLow])
		}
		let blockedRequest = try await transport.waitForSentNode(at: 0)
		await enqueueAppStatePatchResponse(
			patch,
			requestID: try #require(blockedRequest.attrs["id"]),
			transport: transport
		)

		let snapshotRetryRequest = try await transport.waitForSentNode(at: 1)
		let snapshotRetryCollection = snapshotRetryRequest.firstChild(named: "sync")?.firstChild(named: "collection")
		#expect(snapshotRetryCollection?.attrs["name"] == "regular_low")
		#expect(snapshotRetryCollection?.attrs["return_snapshot"] == "true")
		await enqueueAppStatePatchResponse(
			patch,
			requestID: try #require(snapshotRetryRequest.attrs["id"]),
			transport: transport
		)
		_ = try await blockedTask.value

		try await client.storeAppStateSyncKeys(ReceivedAppStateSyncKeyShareContent(keys: [
			ReceivedAppStateSyncKeyContent(
				keyID: try appStateHexData("0102030405060708"),
				keyIDBase64: nil,
				keyData: Data((0..<32).map(UInt8.init)),
				fingerprint: nil,
				timestamp: nil
			)
		]))

		let retryRequest = try await transport.waitForSentNode(at: 2)
		#expect(retryRequest.firstChild(named: "sync")?.firstChild(named: "collection")?.attrs["name"] == "regular_low")
		await enqueueAppStatePatchResponse(
			patch,
			requestID: try #require(retryRequest.attrs["id"]),
			transport: transport
		)
		let storedState = try await waitForAppStatePatchState(collection: "regular_low", keys: keys)
		#expect(storedState == encoded.state)
	}

	@Test("sync app state emits label edit updates")
	func syncAppStateEmitsLabelEditUpdates() async throws {
		var appStateKeyData = Proto_Message.AppStateSyncKeyData()
		appStateKeyData.keyData = Data((0..<32).map(UInt8.init))
		let keys = InMemorySignalKeyStore(storage: [
			.appStateSyncKey: ["AQIDBAUGBwg=": try appStateKeyData.serializedData()]
		])
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: appStateCredentials(), keys: keys),
			transportFactory: { _ in transport }
		)
		let encoded = try AppStatePatchEncoder.encode(
			ChatModificationPatchBuilder.patch(for: .labelEdit(
				id: "label-1",
				name: "Urgent",
				color: 5,
				predefinedID: 7,
				deleted: false
			)),
			keyID: try appStateHexData("0102030405060708"),
			keys: try appStateFixtureKeys(),
			state: AppStatePatchState(),
			iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)
		var patch = encoded.patch
		patch.version.version = encoded.state.version
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.regular])
		}
		let request = try await transport.waitForSentNode()
		await enqueueAppStatePatchResponse(
			patch,
			collection: "regular",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .labelEdited(LabelUpdate(
			id: "label-1",
			name: "Urgent",
			color: 5,
			deleted: false,
			predefinedID: "7"
		)))
	}

	@Test("sync app state emits mute chat updates")
	func syncAppStateEmitsMuteChatUpdates() async throws {
		var appStateKeyData = Proto_Message.AppStateSyncKeyData()
		appStateKeyData.keyData = Data((0..<32).map(UInt8.init))
		let keys = InMemorySignalKeyStore(storage: [
			.appStateSyncKey: ["AQIDBAUGBwg=": try appStateKeyData.serializedData()]
		])
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: appStateCredentials(), keys: keys),
			transportFactory: { _ in transport }
		)
		let encoded = try AppStatePatchEncoder.encode(
			ChatModificationPatchBuilder.patch(for: .mute(
				jid: "123@s.whatsapp.net",
				muteEndTimestamp: 1_800_000_000
			)),
			keyID: try appStateHexData("0102030405060708"),
			keys: try appStateFixtureKeys(),
			state: AppStatePatchState(),
			iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)
		var patch = encoded.patch
		patch.version.version = encoded.state.version
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.regularHigh])
		}
		let request = try await transport.waitForSentNode()
		await enqueueAppStatePatchResponse(
			patch,
			collection: "regular_high",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .chatsUpdated([
			ChatUpdate(id: "123@s.whatsapp.net", muteEndTime: 1_800_000_000)
		]))
	}

	@Test("sync app state emits pinned chat updates")
	func syncAppStateEmitsPinnedChatUpdates() async throws {
		var appStateKeyData = Proto_Message.AppStateSyncKeyData()
		appStateKeyData.keyData = Data((0..<32).map(UInt8.init))
		let keys = InMemorySignalKeyStore(storage: [
			.appStateSyncKey: ["AQIDBAUGBwg=": try appStateKeyData.serializedData()]
		])
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: appStateCredentials(), keys: keys),
			transportFactory: { _ in transport }
		)
		let encoded = try AppStatePatchEncoder.encode(
			ChatModificationPatchBuilder.patch(for: .pin(jid: "123@s.whatsapp.net", pinned: true)),
			keyID: try appStateHexData("0102030405060708"),
			keys: try appStateFixtureKeys(),
			state: AppStatePatchState(),
			iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)
		var patch = encoded.patch
		patch.version.version = encoded.state.version
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.regularLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueAppStatePatchResponse(
			patch,
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .chatsUpdated([
			ChatUpdate(id: "123@s.whatsapp.net", pinned: 0)
		]))
	}

	@Test("sync app state emits label association updates")
	func syncAppStateEmitsLabelAssociationUpdates() async throws {
		var appStateKeyData = Proto_Message.AppStateSyncKeyData()
		appStateKeyData.keyData = Data((0..<32).map(UInt8.init))
		let keys = InMemorySignalKeyStore(storage: [
			.appStateSyncKey: ["AQIDBAUGBwg=": try appStateKeyData.serializedData()]
		])
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: appStateCredentials(), keys: keys),
			transportFactory: { _ in transport }
		)
		let encoded = try AppStatePatchEncoder.encode(
			ChatModificationPatchBuilder.patch(for: .messageLabel(
				jid: "123@s.whatsapp.net",
				messageID: "3EB0LABELTARGET",
				labelID: "label-1",
				labeled: false
			)),
			keyID: try appStateHexData("0102030405060708"),
			keys: try appStateFixtureKeys(),
			state: AppStatePatchState(),
			iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)
		var patch = encoded.patch
		patch.version.version = encoded.state.version
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.regular])
		}
		let request = try await transport.waitForSentNode()
		await enqueueAppStatePatchResponse(
			patch,
			collection: "regular",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .labelAssociationUpdated(LabelAssociationUpdate(
			association: .message(
				chatID: "123@s.whatsapp.net",
				messageID: "3EB0LABELTARGET",
				labelID: "label-1"
			),
			type: .remove
		)))
	}
}

private func enqueueAppStatePatchResponse(
	_ patch: Proto_SyncdPatch,
	collection: String = "regular_low",
	requestID: String,
	transport: MockProfileWebSocketTransport
) async {
	await transport.enqueueInbound(BinaryNode(
		tag: "iq",
		attrs: ["id": requestID, "type": "result"],
		content: .nodes([
			BinaryNode(tag: "sync", content: .nodes([
				BinaryNode(
					tag: "collection",
					attrs: ["name": collection, "version": "0", "has_more_patches": "false"],
					content: .nodes([
						BinaryNode(tag: "patch", content: .data(try! patch.serializedData()))
					])
				)
			]))
		])
	))
}

private func waitForAppStatePatchState(
	collection: String,
	keys: InMemorySignalKeyStore
) async throws -> AppStatePatchState {
	for _ in 0..<100 {
		let stored = try await keys.get(.appStateSyncVersion, ids: [collection])
		if let data = stored[collection] {
			return try JSONDecoder().decode(AppStatePatchState.self, from: data)
		}

		try await Task.sleep(for: .milliseconds(1))
	}

	throw AppStatePatchDecoderError.missingPatchVersion
}

private actor StubAppStateBlobTransport: MediaDownloading {
	private let data: Data
	private(set) var urls: [URL] = []

	init(data: Data) {
		self.data = data
	}

	func download(from url: URL) async throws -> Data {
		urls.append(url)
		return data
	}
}
