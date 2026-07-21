import Foundation
import Compression
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client LID mappings")
struct WhatsAppClientLIDMappingTests {
	@Test("incoming Signal decryption uses stored LID mappings")
	func incomingSignalDecryptionUsesStoredLIDMappings() async throws {
		let keys = InMemorySignalKeyStore()
		try await LIDMappingStore.store([
			LIDMapping(pn: "123@s.whatsapp.net", lid: "123@lid")
		], in: keys)
		let plaintext = try MessageEncoder(randomByte: { 0x00 }).encode(
			MessageContentBuilder.text("hello through mapped lid")
		)
		let signalDecryptor = LIDMappingSignalDecryptor(result: plaintext)
		let dependencies = WhatsAppClientMessageDependencies(
			messageEncryptor: LIDMappingMessageEncryptor(),
			messageDeviceResolver: LIDMappingDeviceResolver(),
			signalSessionPreparer: LIDMappingSessionPreparer(),
			incomingSignalDecryptor: signalDecryptor
		)
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: lidMappingCredentials(),
				keys: keys
			)
		)
		var events = client.events.makeAsyncIterator()

		await client.configureMessageDependencies(dependencies)
		await client.handleIncomingNode(BinaryNode(
			tag: "message",
			attrs: ["id": "incoming-mapped-lid", "from": "123@s.whatsapp.net"],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0xaa, 0xbb])))
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "incoming-mapped-lid",
			from: "123@s.whatsapp.net",
			timestamp: nil,
			content: .text("hello through mapped lid")
		)))
		#expect(await signalDecryptor.directJIDs == ["123@lid"])
	}

	@Test("contact app-state mappings are persisted")
	func contactAppStateMappingsArePersisted() async throws {
		let (client, transport) = try appStateMutationClient()
		let patch = try encodedMutationPatch(.contact(
			jid: "123@s.whatsapp.net",
			contact: ChatModificationContact(
				fullName: "Americo Junior",
				firstName: "Americo",
				lidJid: "123@lid",
				pnJid: "123@s.whatsapp.net",
				username: "americo"
			)
		))
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.criticalUnblockLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "critical_unblock_low",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		_ = await events.next()
		#expect(await events.next() == .lidMappingUpdated(LIDMapping(pn: "123@s.whatsapp.net", lid: "123@lid")))
		let keys = try #require(await client.authenticationState?.keys)
		#expect(try await LIDMappingStore.lid(for: "123:7@s.whatsapp.net", in: keys) == "123@lid")
	}

	@Test("PN for LID app-state mappings are persisted")
	func pnForLIDAppStateMappingsArePersisted() async throws {
		let (client, transport) = try appStateMutationClient()
		var mapping = Proto_SyncActionValue.PnForLidChatAction()
		mapping.pnJid = "123@s.whatsapp.net"
		var action = Proto_SyncActionValue()
		action.pnForLidChatAction = mapping
		let patch = try encodedMutationPatch(
			action: action,
			index: ["pn_for_lid_chat", "123@lid"],
			type: .regularHigh
		)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.regularHigh])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "regular_high",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .lidMappingUpdated(LIDMapping(pn: "123@s.whatsapp.net", lid: "123@lid")))
		let keys = try #require(await client.authenticationState?.keys)
		#expect(try await LIDMappingStore.lid(for: "123@s.whatsapp.net", in: keys) == "123@lid")
	}

	@Test("history sync mappings are persisted")
	func historySyncMappingsArePersisted() async throws {
		let keys = InMemorySignalKeyStore()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: lidMappingCredentials(), keys: keys),
			messageDecryptor: LIDMappingHistoryDecryptor(
				message: try lidMappingHistoryNotificationMessage()
			)
		)

		await client.handleIncomingNode(lidMappingEncryptedMessageNode(id: "history-lid-mapping"))

		#expect(try await LIDMappingStore.lid(for: "555@s.whatsapp.net", in: keys) == "555@lid")
	}

	@Test("LID migration sync mappings are persisted")
	func lidMigrationSyncMappingsArePersisted() async throws {
		let keys = InMemorySignalKeyStore()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: lidMappingCredentials(), keys: keys),
			messageDecryptor: LIDMappingHistoryDecryptor(
				message: try lidMigrationSyncMessage()
			)
		)

		await client.handleIncomingNode(lidMappingEncryptedMessageNode(id: "lid-migration-sync"))

		#expect(try await LIDMappingStore.lid(for: "55111@s.whatsapp.net", in: keys) == "99222@lid")
		#expect(try await LIDMappingStore.lid(for: "55333@s.whatsapp.net", in: keys) == "99555@lid")
	}
}

private struct LIDMappingHistoryDecryptor: IncomingMessageDecrypting {
	let message: Proto_Message

	func decryptIncomingMessage(from node: BinaryNode) async throws -> Proto_Message? {
		message
	}
}

private struct LIDMappingMessageEncryptor: MessageEncrypting {
	func encryptMessage(jid: String, data: Data) async throws -> EncryptedMessage {
		EncryptedMessage(type: "msg", ciphertext: data)
	}
}

private struct LIDMappingDeviceResolver: MessageDeviceResolving {
	func deviceJIDs(for jid: String) async throws -> [String] {
		[jid]
	}
}

private struct LIDMappingSessionPreparer: SignalSessionPreparing {
	func assertSessions(for jids: [String], force: Bool) async throws -> Bool {
		!jids.isEmpty
	}
}

private actor LIDMappingSignalDecryptor: SignalMessageDecrypting {
	private let result: Data
	private(set) var directJIDs: [String] = []

	init(result: Data) {
		self.result = result
	}

	func decryptMessage(jid: String, type: String, ciphertext: Data) async throws -> Data {
		directJIDs.append(jid)
		return result
	}

	func decryptGroupMessage(group: String, authorJID: String, ciphertext: Data) async throws -> Data {
		result
	}

	func processSenderKeyDistributionMessage(authorJID: String, messageData: Data) async throws {}
}

private func lidMappingHistoryNotificationMessage() throws -> Proto_Message {
	var mapping = Proto_PhoneNumberToLIDMapping()
	mapping.pnJid = "555@s.whatsapp.net"
	mapping.lidJid = "555@lid"
	var history = Proto_HistorySync()
	history.syncType = .recent
	history.phoneNumberToLidMappings = [mapping]
	var notification = Proto_Message.HistorySyncNotification()
	notification.syncType = .recent
	notification.initialHistBootstrapInlinePayload = try lidMappingZlibCompress(history.serializedData())
	var protocolMessage = Proto_Message.ProtocolMessageMessage()
	protocolMessage.type = .historySyncNotification
	protocolMessage.historySyncNotification = notification
	var message = Proto_Message()
	message.protocolMessage = protocolMessage
	return message
}

private func lidMigrationSyncMessage() throws -> Proto_Message {
	var assignedMapping = Proto_LIDMigrationMapping()
	assignedMapping.pn = 55_111
	assignedMapping.assignedLid = 99_222
	var latestMapping = Proto_LIDMigrationMapping()
	latestMapping.pn = 55_333
	latestMapping.assignedLid = 99_444
	latestMapping.latestLid = 99_555
	var payload = Proto_LIDMigrationMappingSyncPayload()
	payload.pnToLidMappings = [assignedMapping, latestMapping]
	var sync = Proto_LIDMigrationMappingSyncMessage()
	sync.encodedMappingPayload = try payload.serializedData()
	var protocolMessage = Proto_Message.ProtocolMessageMessage()
	protocolMessage.type = .lidMigrationMappingSync
	protocolMessage.lidMigrationMappingSyncMessage = sync
	var message = Proto_Message()
	message.protocolMessage = protocolMessage
	return message
}

private func lidMappingEncryptedMessageNode(id: String) -> BinaryNode {
	BinaryNode(
		tag: "message",
		attrs: ["id": id, "from": "123@s.whatsapp.net", "t": "1700000007"],
		content: .nodes([
			BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0xaa, 0xbb])))
		])
	)
}

private func lidMappingZlibCompress(_ data: Data) throws -> Data {
	var capacity = max(64, data.count * 2)
	while capacity < 1024 * 1024 {
		var output = Data(count: capacity)
		let encodedCount = output.withUnsafeMutableBytes { outputBuffer in
			data.withUnsafeBytes { inputBuffer in
				compression_encode_buffer(
					outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
					capacity,
					inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
					data.count,
					nil,
					COMPRESSION_ZLIB
				)
			}
		}
		if encodedCount > 0 {
			output.removeSubrange(encodedCount..<output.count)
			return output
		}
		capacity *= 2
	}
	throw LIDMappingTestError.compressionFailed
}

private enum LIDMappingTestError: Error {
	case compressionFailed
}

private func lidMappingCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
		signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data([6])),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([8])),
			signature: Data([9]),
			keyID: 10
		),
		registrationID: 11,
		advSecretKey: "secret",
		me: WhatsAppUser(id: "999@s.whatsapp.net"),
		nextPreKeyID: 12,
		firstUnuploadedPreKeyID: 13,
		accountSyncCounter: 0,
		registered: true
	)
}
