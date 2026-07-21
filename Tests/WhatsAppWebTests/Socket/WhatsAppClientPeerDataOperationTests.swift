import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client peer data operations")
struct WhatsAppClientPeerDataOperationTests {
	@Test("requests on demand message history through peer data operation messages")
	func requestsOnDemandMessageHistoryThroughPeerDataOperationMessages() async throws {
		let transport = MockWebSocketTransport()
		let encryptor = PeerDataOperationEncryptor()
		let deviceResolver = PeerDataOperationDeviceResolver(result: ["555:0@s.whatsapp.net"])
		let sessionPreparer = PeerDataOperationSessionPreparer()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: peerDataOperationCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: sessionPreparer,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		let messageID = try await client.requestMessageHistory(
			count: 25,
			oldestMessageKey: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: false,
				id: "oldest-message",
				participant: "456@s.whatsapp.net"
			),
			oldestMessageTimestampMilliseconds: 1_700_000_000_123,
			messageID: "3EB0PEERDATA"
		)

		let encryptedCalls = await encryptor.calls
		let encodedMessage = try #require(encryptedCalls.first?.data)
		let protobufMessage = try Proto_Message(serializedBytes: encodedMessage.dropLast())
		let request = protobufMessage.protocolMessage.peerDataOperationRequestMessage
		#expect(messageID == "3EB0PEERDATA")
		#expect(await deviceResolver.calls == ["555@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			PeerDataOperationSessionCall(jids: ["555:0@s.whatsapp.net"], force: false)
		])
		#expect(protobufMessage.protocolMessage.type == .peerDataOperationRequestMessage)
		#expect(request.peerDataOperationRequestType == .historySyncOnDemand)
		#expect(request.historySyncOnDemandRequest.chatJid == "123@s.whatsapp.net")
		#expect(request.historySyncOnDemandRequest.oldestMsgFromMe == false)
		#expect(request.historySyncOnDemandRequest.oldestMsgID == "oldest-message")
		#expect(request.historySyncOnDemandRequest.oldestMsgTimestampMs == 1_700_000_000_123)
		#expect(request.historySyncOnDemandRequest.onDemandMsgCount == 25)

		var codec = NoiseFrameCodec()
		let stanza = try BinaryNodeDecoder().decode(codec.decode(await transport.sentFrames[0])[0])
		#expect(stanza.attrs["id"] == "3EB0PEERDATA")
		#expect(stanza.attrs["to"] == "555@s.whatsapp.net")
		#expect(stanza.attrs["category"] == "peer")
		#expect(stanza.attrs["push_priority"] == "high_force")
		#expect(stanza.firstChild(named: "meta")?.attrs["appdata"] == "default")
	}

	@Test("Baileys fetchMessageHistory alias requests on demand message history")
	func baileysFetchMessageHistoryAliasRequestsOnDemandMessageHistory() async throws {
		let transport = MockWebSocketTransport()
		let encryptor = PeerDataOperationEncryptor()
		let deviceResolver = PeerDataOperationDeviceResolver(result: ["555:0@s.whatsapp.net"])
		let sessionPreparer = PeerDataOperationSessionPreparer()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: peerDataOperationCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: sessionPreparer,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		let messageID = try await client.fetchMessageHistory(
			count: 3,
			oldestMessageKey: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: true,
				id: "oldest-self-message"
			),
			oldestMessageTimestampMilliseconds: 1_700_000_000_999,
			messageID: "3EB0FETCHHISTORY"
		)

		let encodedMessage = try #require(await encryptor.calls.first?.data)
		let protobufMessage = try Proto_Message(serializedBytes: encodedMessage.dropLast())
		let request = protobufMessage.protocolMessage.peerDataOperationRequestMessage.historySyncOnDemandRequest
		#expect(messageID == "3EB0FETCHHISTORY")
		#expect(request.chatJid == "123@s.whatsapp.net")
		#expect(request.oldestMsgFromMe)
		#expect(request.oldestMsgID == "oldest-self-message")
		#expect(request.oldestMsgTimestampMs == 1_700_000_000_999)
		#expect(request.onDemandMsgCount == 3)
	}

	@Test("requests placeholder message resend through peer data operation messages")
	func requestsPlaceholderMessageResendThroughPeerDataOperationMessages() async throws {
		let transport = MockWebSocketTransport()
		let encryptor = PeerDataOperationEncryptor()
		let deviceResolver = PeerDataOperationDeviceResolver(result: ["555:0@s.whatsapp.net"])
		let sessionPreparer = PeerDataOperationSessionPreparer()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: peerDataOperationCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: sessionPreparer,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		let messageID = try await client.requestPlaceholderResend(
			for: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: false,
				id: "placeholder-message",
				participant: "456@s.whatsapp.net"
			),
			messageID: "3EB0PLACEHOLDER"
		)

		let encryptedCalls = await encryptor.calls
		let encodedMessage = try #require(encryptedCalls.first?.data)
		let protobufMessage = try Proto_Message(serializedBytes: encodedMessage.dropLast())
		let request = protobufMessage.protocolMessage.peerDataOperationRequestMessage
		let resendRequest = try #require(request.placeholderMessageResendRequest.first)
		#expect(messageID == "3EB0PLACEHOLDER")
		#expect(protobufMessage.protocolMessage.type == .peerDataOperationRequestMessage)
		#expect(request.peerDataOperationRequestType == .placeholderMessageResend)
		#expect(request.placeholderMessageResendRequest.count == 1)
		#expect(resendRequest.messageKey.remoteJid == "123@s.whatsapp.net")
		#expect(resendRequest.messageKey.fromMe == false)
		#expect(resendRequest.messageKey.id == "placeholder-message")
		#expect(resendRequest.messageKey.participant == "456@s.whatsapp.net")

		var codec = NoiseFrameCodec()
		let stanza = try BinaryNodeDecoder().decode(codec.decode(await transport.sentFrames[0])[0])
		#expect(stanza.attrs["id"] == "3EB0PLACEHOLDER")
		#expect(stanza.attrs["to"] == "555@s.whatsapp.net")
		#expect(stanza.attrs["category"] == "peer")
		#expect(stanza.attrs["push_priority"] == "high_force")
		#expect(stanza.firstChild(named: "meta")?.attrs["appdata"] == "default")
	}

	@Test("automatically requests placeholder resend for received placeholder messages")
	func automaticallyRequestsPlaceholderResendForReceivedPlaceholderMessages() async throws {
		let transport = MockWebSocketTransport()
		let encryptor = PeerDataOperationEncryptor()
		let deviceResolver = PeerDataOperationDeviceResolver(result: ["555:0@s.whatsapp.net"])
		let sessionPreparer = PeerDataOperationSessionPreparer()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: peerDataOperationCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDecryptor: PeerDataOperationPlaceholderDecryptor(),
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: sessionPreparer,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "message",
			attrs: [
				"id": "placeholder-incoming",
				"from": "123@s.whatsapp.net",
				"type": "text"
			],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0x01])))
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "placeholder-incoming",
			from: "123@s.whatsapp.net",
			timestamp: nil,
			content: .placeholder(ReceivedPlaceholderContent(type: .maskLinkedDevices))
		)))

		let encodedMessage = try #require((await encryptor.calls).first?.data)
		let protobufMessage = try Proto_Message(serializedBytes: encodedMessage.dropLast())
		let request = protobufMessage.protocolMessage.peerDataOperationRequestMessage
		let resendRequest = try #require(request.placeholderMessageResendRequest.first)
		#expect(await deviceResolver.calls == ["555@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			PeerDataOperationSessionCall(jids: ["555:0@s.whatsapp.net"], force: false)
		])
		#expect(request.peerDataOperationRequestType == .placeholderMessageResend)
		#expect(resendRequest.messageKey.remoteJid == "123@s.whatsapp.net")
		#expect(resendRequest.messageKey.fromMe == false)
		#expect(resendRequest.messageKey.id == "placeholder-incoming")

		let peerStanza = try await peerDataStanza(from: transport)
		#expect(peerStanza.attrs["to"] == "555@s.whatsapp.net")
		#expect(peerStanza.attrs["category"] == "peer")
		#expect(peerStanza.attrs["push_priority"] == "high_force")
	}

	@Test("emits recovered placeholder resend messages from peer data responses")
	func emitsRecoveredPlaceholderResendMessagesFromPeerDataResponses() async throws {
		let recovered = ReceivedMessage(
			id: "recovered-placeholder",
			from: "123@s.whatsapp.net",
			timestamp: 1_700_000_011,
			content: .text("recovered content"),
			fromMe: false
		)
		let responseContent = ReceivedPeerDataOperationRequestResponseContent(
			stanzaID: "placeholder-response",
			placeholderResendMessages: [recovered]
		)
		let client = WhatsAppClient(messageDecryptor: PeerDataOperationResponseDecryptor())
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "message",
			attrs: [
				"id": "peer-data-envelope",
				"from": "555@s.whatsapp.net",
				"t": "1700000012"
			],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(try peerDataResponsePlaintext()))
			])
		))

		#expect(await events.next() == .receivedMessage(recovered))
		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "peer-data-envelope",
			from: "555@s.whatsapp.net",
			timestamp: 1_700_000_012,
			content: .peerDataOperationRequestResponse(responseContent)
		)))
	}
}

private actor PeerDataOperationEncryptor: MessageEncrypting {
	private(set) var calls: [PeerDataOperationEncryptionCall] = []

	func encryptMessage(jid: String, data: Data) async throws -> EncryptedMessage {
		calls.append(PeerDataOperationEncryptionCall(jid: jid, data: data))
		return EncryptedMessage(type: "msg", ciphertext: Data([0xaa]))
	}
}

private struct PeerDataOperationEncryptionCall: Equatable, Sendable {
	let jid: String
	let data: Data
}

private actor PeerDataOperationDeviceResolver: MessageDeviceResolving {
	private let result: [String]
	private(set) var calls: [String] = []

	init(result: [String]) {
		self.result = result
	}

	func deviceJIDs(for jid: String) async throws -> [String] {
		calls.append(jid)
		return result
	}
}

private actor PeerDataOperationSessionPreparer: SignalSessionPreparing {
	private(set) var calls: [PeerDataOperationSessionCall] = []

	func assertSessions(for jids: [String], force: Bool) async throws -> Bool {
		calls.append(PeerDataOperationSessionCall(jids: jids, force: force))
		return true
	}
}

private struct PeerDataOperationSessionCall: Equatable, Sendable {
	let jids: [String]
	let force: Bool
}

private struct PeerDataOperationPlaceholderDecryptor: IncomingMessageDecrypting {
	func decryptIncomingMessage(from node: BinaryNode) async throws -> Proto_Message? {
		var placeholder = Proto_Message.PlaceholderMessage()
		placeholder.type = .maskLinkedDevices
		var message = Proto_Message()
		message.placeholderMessage = placeholder
		return message
	}
}

private struct PeerDataOperationResponseDecryptor: IncomingMessageDecrypting {
	func decryptIncomingMessage(from node: BinaryNode) async throws -> Proto_Message? {
		try Proto_Message(serializedBytes: peerDataResponsePlaintext())
	}
}

private func peerDataResponsePlaintext() throws -> Data {
	var recoveredKey = Proto_MessageKey()
	recoveredKey.remoteJid = "123@s.whatsapp.net"
	recoveredKey.fromMe = false
	recoveredKey.id = "recovered-placeholder"
	var recoveredContent = Proto_Message()
	recoveredContent.conversation = "recovered content"
	var recoveredInfo = Proto_WebMessageInfo()
	recoveredInfo.key = recoveredKey
	recoveredInfo.message = recoveredContent
	recoveredInfo.messageTimestamp = 1_700_000_011
	var placeholderResponse = Proto_Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.PlaceholderMessageResendResponse()
	placeholderResponse.webMessageInfoBytes = try recoveredInfo.serializedData()
	var result = Proto_Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult()
	result.placeholderMessageResendResponse = placeholderResponse
	var response = Proto_Message.PeerDataOperationRequestResponseMessage()
	response.stanzaID = "placeholder-response"
	response.peerDataOperationResult = [result]
	var protocolMessage = Proto_Message.ProtocolMessageMessage()
	protocolMessage.type = .peerDataOperationRequestResponseMessage
	protocolMessage.peerDataOperationRequestResponseMessage = response
	var message = Proto_Message()
	message.protocolMessage = protocolMessage
	return try message.serializedData()
}

private func peerDataStanza(from transport: MockWebSocketTransport) async throws -> BinaryNode {
	for _ in 0..<100 {
		let frames = await transport.sentFrames
		var codec = NoiseFrameCodec()
		for frame in frames {
			let stanza = try BinaryNodeDecoder().decode(codec.decode(frame)[0])
			if stanza.tag == "message", stanza.attrs["category"] == "peer" {
				return stanza
			}
		}
		try await Task.sleep(nanoseconds: 10_000_000)
	}

	throw PeerDataOperationTestError.missingPeerDataStanza
}

private enum PeerDataOperationTestError: Error {
	case missingPeerDataStanza
}

private func peerDataOperationCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
		signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data([6])),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([8])),
			signature: Data([9]),
			keyID: 1
		),
		registrationID: 1,
		advSecretKey: "adv",
		me: WhatsAppUser(id: "555@s.whatsapp.net", name: "Swift"),
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true
	)
}
