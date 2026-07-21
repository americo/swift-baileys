import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client app-state patches")
struct WhatsAppClientAppStateTests {
	@Test("sends app-state patch and persists the next collection state")
	func sendsAppStatePatchAndPersistsTheNextCollectionState() async throws {
		var appStateKeyData = Proto_Message.AppStateSyncKeyData()
		appStateKeyData.keyData = Data([0xaa])
		let initialState = AppStatePatchState(version: 4, hash: Data(repeating: 6, count: 128))
		let keys = InMemorySignalKeyStore(storage: [
			.appStateSyncKey: ["AQIDBAUGBwg=": try appStateKeyData.serializedData()],
			.appStateSyncVersion: ["regular_low": try JSONEncoder().encode(initialState)]
		])
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: appStateCredentials(), keys: keys),
			transportFactory: { _ in transport }
		)
		await client.configureAppStateDependencies(
			keyExpander: StubAppStateKeyExpander(keys: try fixtureKeys()),
			hashMixer: StubAppStateHashMixer(result: Data(repeating: 9, count: 128)),
			randomBytes: { _ in try Data(hexString: "202122232425262728292a2b2c2d2e2f") }
		)
		try await client.connect()

		let task = Task {
			try await client.pinChat("123@s.whatsapp.net", pinned: true, requestID: "app-state-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "app-state-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "w:sync:app:state")
		let collection = try #require(request.firstChild(named: "sync")?.firstChild(named: "collection"))
		#expect(collection.attrs["name"] == "regular_low")
		#expect(collection.attrs["version"] == "4")
		#expect(collection.attrs["return_snapshot"] == "false")
		let patchData = try #require(collection.firstChild(named: "patch")?.contentData)
		let patch = try Proto_SyncdPatch(serializedBytes: patchData)
		#expect(patch.keyID.id == (try Data(hexString: "0102030405060708")))
		#expect(patch.mutations.first?.operation == .set)

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "app-state-1", "type": "result"]))
		try await task.value
		let stored = try await keys.get(.appStateSyncVersion, ids: ["regular_low"])
		let storedState = try JSONDecoder().decode(AppStatePatchState.self, from: try #require(stored["regular_low"]))
		#expect(storedState.version == 5)
		#expect(storedState.hash == Data(repeating: 9, count: 128))
	}

	@Test("public app-state chat modification uses native dependencies by default")
	func publicAppStateChatModificationUsesNativeDependenciesByDefault() async throws {
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
		try await client.connect()

		let task = Task {
			try await client.pinChat("123@s.whatsapp.net", pinned: true, requestID: "app-state-native-1")
		}
		let request = try await transport.waitForSentNode()
		let collection = try #require(request.firstChild(named: "sync")?.firstChild(named: "collection"))
		let patchData = try #require(collection.firstChild(named: "patch")?.contentData)
		let patch = try Proto_SyncdPatch(serializedBytes: patchData)
		#expect(request.attrs["id"] == "app-state-native-1")
		#expect(collection.attrs["name"] == "regular_low")
		#expect(patch.keyID.id == (try Data(hexString: "0102030405060708")))

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "app-state-native-1", "type": "result"]))
		try await task.value
		let stored = try await keys.get(.appStateSyncVersion, ids: ["regular_low"])
		let storedState = try JSONDecoder().decode(AppStatePatchState.self, from: try #require(stored["regular_low"]))
		#expect(storedState.version == 1)
		#expect(storedState.hash != Data(repeating: 0, count: 128))
	}

	@Test("public app-state wrappers send the expected collection")
	func publicAppStateWrappersSendTheExpectedCollection() async throws {
		try await expectPublicAppStateWrapperCollection("regular_high", requestID: "mute-chat") {
			try await $0.muteChat("123@s.whatsapp.net", until: 1_718_000_000, requestID: "mute-chat")
		}
		try await expectPublicAppStateWrapperCollection("regular_high", requestID: "unmute-chat") {
			try await $0.unmuteChat("123@s.whatsapp.net", requestID: "unmute-chat")
		}
		try await expectPublicAppStateWrapperCollection("regular_low", requestID: "archive-chat") {
			try await $0.archiveChat(
				"123@s.whatsapp.net",
				archived: true,
				messageRange: AppStateChatMessageRange(lastMessageTimestamp: 60),
				requestID: "archive-chat"
			)
		}
		try await expectPublicAppStateWrapperCollection("regular_low", requestID: "mark-read") {
			try await $0.markChatRead(
				"123@s.whatsapp.net",
				read: true,
				messageRange: AppStateChatMessageRange(lastMessageTimestamp: 60),
				requestID: "mark-read"
			)
		}
		try await expectPublicAppStateWrapperCollection("regular_high", requestID: "clear-chat") {
			try await $0.clearChat(
				"123@s.whatsapp.net",
				messageRange: AppStateChatMessageRange(lastMessageTimestamp: 60),
				requestID: "clear-chat"
			)
		}
		try await expectPublicAppStateWrapperCollection("regular_low", requestID: "pin-chat") {
			try await $0.pinChat("123@s.whatsapp.net", pinned: false, requestID: "pin-chat")
		}
		try await expectPublicAppStateWrapperCollection("critical_block", requestID: "push-name") {
			try await $0.updatePushNameSetting("Swift User", requestID: "push-name")
		}
		try await expectPublicAppStateWrapperCollection("regular", requestID: "disable-link-previews") {
			try await $0.updateDisableLinkPreviewsPrivacy(true, requestID: "disable-link-previews")
		}
		try await expectPublicAppStateWrapperCollection("critical_unblock_low", requestID: "add-contact") {
			try await $0.addOrEditContact("123@s.whatsapp.net", fullName: "Americo Junior", requestID: "add-contact")
		}
		try await expectPublicAppStateWrapperCollection("critical_unblock_low", requestID: "remove-contact") {
			try await $0.removeContact("123@s.whatsapp.net", requestID: "remove-contact")
		}
		try await expectPublicAppStateWrapperCollection("regular_low", requestID: "star-message") {
			try await $0.starMessage(
				jid: "123@s.whatsapp.net",
				messageID: "3EB0STAR",
				fromMe: true,
				starred: true,
				requestID: "star-message"
			)
		}
		try await expectPublicAppStateWrapperCollection("regular_low", requestID: "baileys-star") {
			try await $0.star(
				jid: "123@s.whatsapp.net",
				messages: [BaileysStarMessage(id: "3EB0STAR", fromMe: true)],
				starred: false,
				requestID: "baileys-star"
			)
		}
		try await expectPublicAppStateWrapperCollection("regular_high", requestID: "delete-chat") {
			try await $0.deleteChat(
				"123@s.whatsapp.net",
				messageRange: AppStateChatMessageRange(lastMessageTimestamp: 60),
				requestID: "delete-chat"
			)
		}
		try await expectPublicAppStateWrapperCollection("regular_high", requestID: "delete-for-me") {
			try await $0.deleteMessageForMe(
				jid: "123@s.whatsapp.net",
				messageID: "3EB0DELETE",
				fromMe: false,
				timestamp: 1_718_000_000,
				deleteMedia: true,
				requestID: "delete-for-me"
			)
		}
		try await expectPublicAppStateWrapperCollection("regular", requestID: "set-quick-reply") {
			try await $0.setQuickReply(
				timestamp: "1718000000",
				shortcut: "/hours",
				message: "Open from 8 to 17",
				requestID: "set-quick-reply"
			)
		}
		try await expectPublicAppStateWrapperCollection("regular", requestID: "baileys-quick-reply") {
			try await $0.addOrEditQuickReply(
				BaileysQuickReplyAction(
					timestamp: "1718000001",
					shortcut: "/support",
					message: "Support is online"
				),
				requestID: "baileys-quick-reply"
			)
		}
		try await expectPublicAppStateWrapperCollection("regular", requestID: "delete-quick-reply") {
			try await $0.deleteQuickReply(
				timestamp: "1718000000",
				shortcut: "/hours",
				message: "Open from 8 to 17",
				requestID: "delete-quick-reply"
			)
		}
		try await expectPublicAppStateWrapperCollection("regular", requestID: "baileys-remove-quick-reply") {
			try await $0.removeQuickReply(timestamp: "1718000001", requestID: "baileys-remove-quick-reply")
		}
		try await expectPublicAppStateWrapperCollection("regular", requestID: "edit-label") {
			try await $0.editLabel(id: "label-1", name: "Urgent", color: 5, predefinedID: 7, requestID: "edit-label")
		}
		try await expectPublicAppStateWrapperCollection("regular", requestID: "baileys-add-label") {
			try await $0.addLabel(
				jid: "123@s.whatsapp.net",
				labels: BaileysLabelAction(id: "label-1", name: "Urgent", color: 5, predefinedID: 7),
				requestID: "baileys-add-label"
			)
		}
		try await expectPublicAppStateWrapperCollection("regular", requestID: "delete-label") {
			try await $0.deleteLabel(id: "label-1", requestID: "delete-label")
		}
		try await expectPublicAppStateWrapperCollection("regular", requestID: "add-chat-label") {
			try await $0.addChatLabel(jid: "123@s.whatsapp.net", labelID: "label-1", requestID: "add-chat-label")
		}
		try await expectPublicAppStateWrapperCollection("regular", requestID: "remove-chat-label") {
			try await $0.removeChatLabel(jid: "123@s.whatsapp.net", labelID: "label-1", requestID: "remove-chat-label")
		}
		try await expectPublicAppStateWrapperCollection("regular", requestID: "add-message-label") {
			try await $0.addMessageLabel(
				jid: "123@s.whatsapp.net",
				messageID: "3EB0LABEL",
				labelID: "label-1",
				requestID: "add-message-label"
			)
		}
		try await expectPublicAppStateWrapperCollection("regular", requestID: "remove-message-label") {
			try await $0.removeMessageLabel(
				jid: "123@s.whatsapp.net",
				messageID: "3EB0LABEL",
				labelID: "label-1",
				requestID: "remove-message-label"
			)
		}
	}
}

private func expectPublicAppStateWrapperCollection(
	_ expectedName: String,
	requestID: String,
	operation: @escaping @Sendable (WhatsAppClient) async throws -> Void
) async throws {
	var appStateKeyData = Proto_Message.AppStateSyncKeyData()
	appStateKeyData.keyData = Data([0xaa])
	let keys = InMemorySignalKeyStore(storage: [
		.appStateSyncKey: ["AQIDBAUGBwg=": try appStateKeyData.serializedData()]
	])
	let transport = MockProfileWebSocketTransport()
	let client = WhatsAppClient(
		authenticationState: AuthenticationState(credentials: appStateCredentials(), keys: keys),
		transportFactory: { _ in transport }
	)
	await client.configureAppStateDependencies(
		keyExpander: StubAppStateKeyExpander(keys: try fixtureKeys()),
		hashMixer: StubAppStateHashMixer(result: Data(repeating: 9, count: 128)),
		randomBytes: { _ in try Data(hexString: "202122232425262728292a2b2c2d2e2f") }
	)
	try await client.connect()

	let task = Task {
		try await operation(client)
	}
	let request = try await transport.waitForSentNode()
	let collection = try #require(request.firstChild(named: "sync")?.firstChild(named: "collection"))
	#expect(request.attrs["id"] == requestID)
	#expect(collection.attrs["name"] == expectedName)

	await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": requestID, "type": "result"]))
	try await task.value
	let stored = try await keys.get(.appStateSyncVersion, ids: [expectedName])
	#expect(stored[expectedName] != nil)
}

private struct StubAppStateKeyExpander: AppStateKeyExpanding {
	let keys: AppStatePatchKeySet

	func expand(keyData: Data) throws -> AppStatePatchKeySet {
		keys
	}
}

private struct StubAppStateHashMixer: AppStatePatchHashMixing {
	let result: Data

	func subtractThenAdd(hash: Data, subtract: [Data], add: [Data]) throws -> Data {
		result
	}
}

private func fixtureKeys() throws -> AppStatePatchKeySet {
	AppStatePatchKeySet(
		indexKey: try Data(hexString: "61387bcf643616a68bd611a45516b3980418323087d78bf08c615645549434b4"),
		valueEncryptionKey: try Data(hexString: "900ba2843ba5fb0cee55cf2a4de9503dce68187d3f6b95b420b008bde66f5a20"),
		valueMacKey: try Data(hexString: "d0879f6b61f0bcba79faad3f47a8a768fd7fc04a6cc8b3ecefedfa087413226f"),
		snapshotMacKey: try Data(hexString: "69b2e91be6587307c43c29b027a71fdd55be25f07ca726714115430d23093071"),
		patchMacKey: try Data(hexString: "693845bdd996652aca9ca0b96d0f081abf29943303c5eb19bdb84f38b24c32ab")
	)
}

func appStateCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
		signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data([6])),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([8])),
			signature: Data([9]),
			keyID: 1
		),
		registrationID: 559,
		advSecretKey: "adv-secret",
		me: WhatsAppUser(id: "999@s.whatsapp.net", name: "Swift User", lid: "999@lid"),
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true,
		myAppStateKeyID: "AQIDBAUGBwg="
	)
}

private extension BinaryNode {
	var contentData: Data? {
		guard case let .data(data) = content else {
			return nil
		}

		return data
	}
}

private extension Data {
	init(hexString: String) throws {
		guard hexString.count.isMultiple(of: 2) else {
			throw HexDataError.invalidLength
		}

		var bytes = [UInt8]()
		bytes.reserveCapacity(hexString.count / 2)
		var index = hexString.startIndex
		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw HexDataError.invalidByte
			}
			bytes.append(byte)
			index = next
		}
		self = Data(bytes)
	}
}

private enum HexDataError: Error {
	case invalidLength
	case invalidByte
}
