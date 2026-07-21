import Foundation
import Compression
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client public dependency receive path")
struct WhatsAppClientPublicDependencyReceiveTests {
	@Test("public message dependencies enable encrypted incoming message parsing")
	func publicMessageDependenciesEnableEncryptedIncomingMessageParsing() async throws {
		let transport = PublicDependencyReceiveTransport()
		let plaintext = try MessageEncoder(randomByte: { 0x00 }).encode(
			MessageContentBuilder.text("hello through public dependencies")
		)
		let dependencies = WhatsAppClientMessageDependencies(
			messageEncryptor: PublicDependencyEncryptor(),
			messageDeviceResolver: PublicDependencyDeviceResolver(),
			signalSessionPreparer: PublicDependencySessionPreparer(),
			incomingSignalDecryptor: PublicDependencySignalDecryptor(result: plaintext)
		)
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: publicDependencyReceiveCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		var events = client.events.makeAsyncIterator()

		await client.configureMessageDependencies(dependencies)
		try await client.connect()
		await transport.enqueue(BinaryNode(
			tag: "message",
			attrs: ["id": "incoming-public-deps", "from": "123@s.whatsapp.net"],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0xaa, 0xbb])))
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "incoming-public-deps",
			from: "123@s.whatsapp.net",
			timestamp: nil,
			content: .text("hello through public dependencies")
		)))
	}

	@Test("history sync notifications emit processed history events")
	func historySyncNotificationsEmitProcessedHistoryEvents() async throws {
		let transport = PublicDependencyReceiveTransport()
		var history = Proto_HistorySync()
		history.syncType = .recent
		history.conversations = [
			receiveHistoryConversation(
				id: "123@s.whatsapp.net",
				messageID: "history-message",
				text: "from history"
			)
		]
		var notification = Proto_Message.HistorySyncNotification()
		notification.syncType = .recent
		notification.chunkOrder = 3
		notification.initialHistBootstrapInlinePayload = try receiveZlibCompress(history.serializedData())
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .historySyncNotification
		protocolMessage.historySyncNotification = notification
		var message = Proto_Message()
		message.protocolMessage = protocolMessage
		let plaintext = try MessageEncoder(randomByte: { 0x00 }).encode(message)
		let dependencies = WhatsAppClientMessageDependencies(
			messageEncryptor: PublicDependencyEncryptor(),
			messageDeviceResolver: PublicDependencyDeviceResolver(),
			signalSessionPreparer: PublicDependencySessionPreparer(),
			incomingSignalDecryptor: PublicDependencySignalDecryptor(result: plaintext)
		)
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: publicDependencyReceiveCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		var events = client.events.makeAsyncIterator()

		await client.configureMessageDependencies(dependencies)
		try await client.connect()
		await transport.enqueue(BinaryNode(
			tag: "message",
			attrs: [
				"id": "history-notification",
				"from": "123@s.whatsapp.net",
				"participant": "123:1@s.whatsapp.net",
				"t": "1700000007"
			],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0xaa, 0xbb])))
			])
		))

		let expectedProcessedHistoryMessages = [
			ProcessedHistoryMessage(
				key: WhatsAppMessageKey(
					remoteJID: "123@s.whatsapp.net",
					fromMe: false,
					id: "history-notification",
					participant: "123@s.whatsapp.net"
				),
				messageTimestamp: 1_700_000_007
			)
		]
		guard case .credentialsUpdated(let updatedCredentials)? = await events.next() else {
			Issue.record("Expected credentials update after processed history marker")
			return
		}
		#expect(updatedCredentials.processedHistoryMessages == expectedProcessedHistoryMessages)
		#expect(await events.next() == .messagingHistorySet(MessagingHistorySet(
			chats: [
				HistorySyncChat(
					id: "123@s.whatsapp.net",
					name: nil,
					displayName: nil,
					username: nil,
					lid: nil,
					phoneNumber: nil,
					lastMessageReceivedTimestamp: 1_700_000_006,
					latestMessage: ReceivedMessage(
						id: "history-message",
						from: "123@s.whatsapp.net",
						timestamp: 1_700_000_006,
						content: .text("from history"),
						fromMe: false
					)
				)
			],
			contacts: [
				HistorySyncContact(
					id: "123@s.whatsapp.net",
					name: nil,
					username: nil,
					lid: nil,
					phoneNumber: nil,
					notify: nil,
					verifiedName: nil
				)
			],
			messages: [
				ReceivedMessage(
					id: "history-message",
					from: "123@s.whatsapp.net",
					timestamp: 1_700_000_006,
					content: .text("from history"),
					fromMe: false
				)
			],
			lidPnMappings: [],
			pastParticipants: [],
			syncType: .recent,
			progress: nil,
			chunkOrder: 3,
			peerDataRequestSessionID: nil,
			isLatest: true
		)))
		guard case .receivedMessage(let received)? = await events.next() else {
			Issue.record("Expected received history notification message")
			return
		}
		#expect(received.id == "history-notification")
		#expect(received.participant == "123@s.whatsapp.net")
		#expect(received.content == .historySyncNotification(ReceivedHistorySyncNotificationContent(
			fileSHA256: nil,
			fileLength: nil,
			mediaKey: nil,
			fileEncSHA256: nil,
			directPath: nil,
			syncType: .recent,
			chunkOrder: 3,
			originalMessageID: nil,
			progress: nil,
			oldestMessageInChunkTimestampSeconds: nil,
			initialHistoryBootstrapInlinePayload: notification.initialHistBootstrapInlinePayload,
			peerDataRequestSessionID: nil,
			encryptedHandle: nil,
			messageAccessStatus: nil
		)))
		#expect(await client.authenticationState?.credentials.processedHistoryMessages == expectedProcessedHistoryMessages)
	}

	@Test("history sync notifications emit complete status milestones once")
	func historySyncNotificationsEmitCompleteStatusMilestonesOnce() async throws {
		let client = WhatsAppClient(messageDecryptor: PublicDependencyHistoryDecryptor(
			message: try receiveHistoryNotificationMessage(syncType: .recent, progress: 100)
		))
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(receiveEncryptedMessageNode(id: "recent-history-1"))
		#expect(await events.next() == .messagingHistoryStatus(MessagingHistoryStatusUpdate(
			syncType: .recent,
			status: .complete,
			explicit: true
		)))
		guard case .messagingHistorySet(let firstSet)? = await events.next() else {
			Issue.record("Expected first recent history set")
			return
		}
		#expect(firstSet.syncType == .recent)
		#expect(firstSet.progress == 100)
		guard case .receivedMessage(let firstEnvelope)? = await events.next() else {
			Issue.record("Expected first recent history envelope")
			return
		}
		#expect(firstEnvelope.id == "recent-history-1")

		await client.handleIncomingNode(receiveEncryptedMessageNode(id: "recent-history-2"))
		guard case .messagingHistorySet(let secondSet)? = await events.next() else {
			Issue.record("Expected second recent history set without duplicate status")
			return
		}
		#expect(secondSet.syncType == .recent)
		guard case .receivedMessage(let secondEnvelope)? = await events.next() else {
			Issue.record("Expected second recent history envelope")
			return
		}
		#expect(secondEnvelope.id == "recent-history-2")
	}

	@Test("initial bootstrap history sync emits complete status without progress")
	func initialBootstrapHistorySyncEmitsCompleteStatusWithoutProgress() async throws {
		let client = WhatsAppClient(messageDecryptor: PublicDependencyHistoryDecryptor(
			message: try receiveHistoryNotificationMessage(syncType: .initialBootstrap)
		))
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(receiveEncryptedMessageNode(id: "initial-history"))

		#expect(await events.next() == .messagingHistoryStatus(MessagingHistoryStatusUpdate(
			syncType: .initialBootstrap,
			status: .complete,
			explicit: true
		)))
		guard case .messagingHistorySet(let set)? = await events.next() else {
			Issue.record("Expected initial bootstrap history set")
			return
		}
		#expect(set.syncType == .initialBootstrap)
	}

	@Test("recent history sync emits paused status after incomplete chunks stop")
	func recentHistorySyncEmitsPausedStatusAfterIncompleteChunksStop() async throws {
		let client = WhatsAppClient(
			configuration: WhatsAppClientConfiguration(historySyncPausedTimeout: .milliseconds(20)),
			messageDecryptor: PublicDependencyHistoryDecryptor(
				message: try receiveHistoryNotificationMessage(syncType: .recent, progress: 45)
			)
		)
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(receiveEncryptedMessageNode(id: "recent-history-paused"))

		guard case .messagingHistorySet(let set)? = await events.next() else {
			Issue.record("Expected incomplete recent history set")
			return
		}
		#expect(set.syncType == .recent)
		#expect(set.progress == 45)
		guard case .receivedMessage(let envelope)? = await events.next() else {
			Issue.record("Expected incomplete recent history envelope")
			return
		}
		#expect(envelope.id == "recent-history-paused")
		#expect(await events.next() == .messagingHistoryStatus(MessagingHistoryStatusUpdate(
			syncType: .recent,
			status: .paused,
			explicit: false
		)))
	}

	@Test("invalid incoming Signal addresses emit typed decryption failures")
	func invalidIncomingSignalAddressesEmitTypedDecryptionFailures() async throws {
		let dependencies = WhatsAppClientMessageDependencies(
			messageEncryptor: PublicDependencyEncryptor(),
			messageDeviceResolver: PublicDependencyDeviceResolver(),
			signalSessionPreparer: PublicDependencySessionPreparer(),
			incomingSignalDecryptor: PublicDependencySignalDecryptor(result: Data())
		)
		let client = WhatsAppClient(messageDependencies: dependencies)
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "message",
			attrs: ["id": "incoming-invalid-address", "from": "not-a-jid"],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0xaa])))
			])
		))

		#expect(await events.next() == .messageDecryptionFailed(MessageDecryptionFailure(
			id: "incoming-invalid-address",
			from: "not-a-jid",
			participant: nil,
			timestamp: nil,
			ciphertextType: "msg",
			reason: .invalidSignalAddress
		)))
	}

	@Test("unsupported direct ciphertext types emit typed decryption failures")
	func unsupportedDirectCiphertextTypesEmitTypedDecryptionFailures() async throws {
		let dependencies = WhatsAppClientMessageDependencies(
			messageEncryptor: PublicDependencyEncryptor(),
			messageDeviceResolver: PublicDependencyDeviceResolver(),
			signalSessionPreparer: PublicDependencySessionPreparer(),
			incomingSignalDecryptor: PublicDependencySignalDecryptor(result: Data())
		)
		let client = WhatsAppClient(messageDependencies: dependencies)
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "message",
			attrs: ["id": "incoming-unknown-type", "from": "123@s.whatsapp.net"],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "unknown"], content: .data(Data([0xaa])))
			])
		))

		#expect(await events.next() == .messageDecryptionFailed(MessageDecryptionFailure(
			id: "incoming-unknown-type",
			from: "123@s.whatsapp.net",
			participant: nil,
			timestamp: nil,
			ciphertextType: "unknown",
			reason: .unsupportedDirectCiphertextType("unknown")
		)))
	}

	@Test("empty incoming ciphertext emits typed decryption failure before Signal")
	func emptyIncomingCiphertextEmitsTypedDecryptionFailureBeforeSignal() async throws {
		let signalDecryptor = PublicDependencySignalDecryptor(result: Data())
		let dependencies = WhatsAppClientMessageDependencies(
			messageEncryptor: PublicDependencyEncryptor(),
			messageDeviceResolver: PublicDependencyDeviceResolver(),
			signalSessionPreparer: PublicDependencySessionPreparer(),
			incomingSignalDecryptor: signalDecryptor
		)
		let client = WhatsAppClient(messageDependencies: dependencies)
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "message",
			attrs: ["id": "incoming-empty-ciphertext", "from": "123@s.whatsapp.net"],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data()))
			])
		))

		#expect(await events.next() == .messageDecryptionFailed(MessageDecryptionFailure(
			id: "incoming-empty-ciphertext",
			from: "123@s.whatsapp.net",
			participant: nil,
			timestamp: nil,
			ciphertextType: "msg",
			reason: .emptyCiphertext
		)))
		#expect(await signalDecryptor.calls.isEmpty)
	}
}

private actor PublicDependencyReceiveTransport: WhatsAppWebSocketTransport {
	private var continuations: [CheckedContinuation<Data?, Error>] = []
	private var frames: [Data?] = []

	func connect() async throws {}
	func send(_ data: Data) async throws {}

	func receive() async throws -> Data? {
		try await withCheckedThrowingContinuation { continuation in
			if !frames.isEmpty {
				continuation.resume(returning: frames.removeFirst())
			} else {
				continuations.append(continuation)
			}
		}
	}

	func close() async {
		resume(nil)
	}

	func enqueue(_ node: BinaryNode) {
		var codec = NoiseFrameCodec()
		resume(codec.encode(try! BinaryNodeEncoder().encode(node)))
	}

	private func resume(_ data: Data?) {
		if continuations.isEmpty {
			frames.append(data)
		} else {
			continuations.removeFirst().resume(returning: data)
		}
	}
}

private struct PublicDependencyEncryptor: MessageEncrypting {
	func encryptMessage(jid: String, data: Data) async throws -> EncryptedMessage {
		EncryptedMessage(type: "msg", ciphertext: data)
	}
}

private struct PublicDependencyDeviceResolver: MessageDeviceResolving {
	func deviceJIDs(for jid: String) async throws -> [String] {
		[jid]
	}
}

private struct PublicDependencySessionPreparer: SignalSessionPreparing {
	func assertSessions(for jids: [String], force: Bool) async throws -> Bool {
		!jids.isEmpty
	}
}

private struct PublicDependencyHistoryDecryptor: IncomingMessageDecrypting {
	let message: Proto_Message

	func decryptIncomingMessage(from node: BinaryNode) async throws -> Proto_Message? {
		message
	}
}

private actor PublicDependencySignalDecryptor: SignalMessageDecrypting {
	private let result: Data
	private(set) var calls: [Data] = []

	init(result: Data) {
		self.result = result
	}

	func decryptMessage(jid: String, type: String, ciphertext: Data) async throws -> Data {
		calls.append(ciphertext)
		return result
	}

	func decryptGroupMessage(group: String, authorJID: String, ciphertext: Data) async throws -> Data {
		calls.append(ciphertext)
		return result
	}

	func processSenderKeyDistributionMessage(authorJID: String, messageData: Data) async throws {}
}

private func receiveHistoryConversation(
	id: String,
	messageID: String,
	text: String
) -> Proto_Conversation {
	var key = Proto_MessageKey()
	key.id = messageID
	key.remoteJid = id
	key.fromMe = false
	var content = Proto_Message()
	content.conversation = text
	var message = Proto_WebMessageInfo()
	message.key = key
	message.message = content
	message.messageTimestamp = 1_700_000_006
	var item = Proto_HistorySyncMsg()
	item.message = message
	var chat = Proto_Conversation()
	chat.id = id
	chat.messages = [item]
	return chat
}

private func receiveHistoryNotificationMessage(
	syncType: Proto_Message.HistorySyncType,
	progress: UInt32? = nil
) throws -> Proto_Message {
	var history = Proto_HistorySync()
	history.syncType = Proto_HistorySync.HistorySyncType(rawValue: syncType.rawValue)
		?? .UNRECOGNIZED(syncType.rawValue)
	if let progress {
		history.progress = progress
	}
	history.conversations = [
		receiveHistoryConversation(
			id: "123@s.whatsapp.net",
			messageID: "history-message",
			text: "from history"
		)
	]
	var notification = Proto_Message.HistorySyncNotification()
	notification.syncType = syncType
	if let progress {
		notification.progress = progress
	}
	notification.initialHistBootstrapInlinePayload = try receiveZlibCompress(history.serializedData())
	var protocolMessage = Proto_Message.ProtocolMessageMessage()
	protocolMessage.type = .historySyncNotification
	protocolMessage.historySyncNotification = notification
	var message = Proto_Message()
	message.protocolMessage = protocolMessage
	return message
}

private func receiveEncryptedMessageNode(id: String) -> BinaryNode {
	BinaryNode(
		tag: "message",
		attrs: [
			"id": id,
			"from": "123@s.whatsapp.net",
			"t": "1700000007"
		],
		content: .nodes([
			BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0xaa, 0xbb])))
		])
	)
}

private func receiveZlibCompress(_ data: Data) throws -> Data {
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
	throw PublicDependencyReceiveTestError.compressionFailed
}

private enum PublicDependencyReceiveTestError: Error {
	case compressionFailed
}

private func publicDependencyReceiveCredentials() -> AuthenticationCredentials {
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
