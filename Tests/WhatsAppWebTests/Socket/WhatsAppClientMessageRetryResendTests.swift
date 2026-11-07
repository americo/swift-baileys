import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client message retry resend")
struct WhatsAppClientMessageRetryResendTests {
	@Test("resends cached direct messages only to the requesting participant")
	func resendsCachedDirectMessagesOnlyToTheRequestingParticipant() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(
			results: [
				EncryptedMessage(type: "msg", ciphertext: Data([0x10])),
				EncryptedMessage(type: "msg", ciphertext: Data([0xab, 0xcd]))
			],
			callOrder: callOrder
		)
		let deviceResolver = StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"])
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: sessionPreparer,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()
		_ = try await client.sendTextMessage(
			to: "123@s.whatsapp.net",
			text: "cached message",
			messageID: "3EB0RETRY"
		)

		let messageID = try await client.resendCachedMessage(
			for: MessageRetryRequest(
				key: WhatsAppMessageKey(
					remoteJID: "123@s.whatsapp.net",
					fromMe: true,
					id: "3EB0RETRY",
					participant: "123:2@s.whatsapp.net"
				),
				messageIDs: ["3EB0RETRY"],
				requesterJID: "123:2@s.whatsapp.net",
				retryCount: 2
			)
		)

		#expect(messageID == "3EB0RETRY")
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false),
			SignalSessionPreparationCall(jids: ["123:2@s.whatsapp.net"], force: true)
		])
		#expect(await callOrder.values == [
			"sessions",
			"encrypt:123.0@s.whatsapp.net",
			"sessions",
			"encrypt:123:2@s.whatsapp.net"
		])

		let stanza = try await retryResendStanza(from: transport)
		#expect(stanza.attrs["id"] == "3EB0RETRY")
		#expect(stanza.attrs["to"] == "123:2@s.whatsapp.net")
		#expect(stanza.attrs["participant"] == nil)
		#expect(stanza.attrs["recipient"] == nil)
		#expect(stanza.firstChild(named: "participants") == nil)
		#expect(stanza.firstChild(named: "enc")?.attrs["count"] == "2")
		#expect(stanza.firstChild(named: "enc")?.content == .data(Data([0xab, 0xcd])))
	}

	@Test("a resent poll still says it is a poll", arguments: ["creation", "vote"])
	func resentPollKeepsItsMeta(pollType: String) async throws {
		let client = WhatsAppClient(transportFactory: { _ in MockMessageSendWebSocketTransport() })
		var message = Proto_Message()
		message.pollUpdateMessage = Proto_Message.PollUpdateMessage()
		await client.cacheRecentSentMessage(
			destinationJID: "123@s.whatsapp.net",
			id: "3EB0POLL",
			message: message,
			additionalNodes: [BinaryNode(tag: "meta", attrs: ["polltype": pollType])]
		)

		let source = try #require(await client.retrySource(requestedDestinationJID: "123@s.whatsapp.net", id: "3EB0POLL"))
		#expect(source.message.peerStanza == nil)

		let stanza = try await MessageRelayBuilder(encoder: MessageEncoder(randomByte: { 0x00 }), encryptor: PeerRecordingEncryptor())
			.buildRetryMessageStanza(
				to: source.destinationJID,
				messageID: "3EB0POLL",
				message: source.message.message,
				participantJID: "123:2@s.whatsapp.net",
				retryCount: 1,
				localUserJID: "999:21@s.whatsapp.net",
				localUserLID: "888:21@lid",
				additionalNodes: source.message.metaNodes
			)
		#expect(stanza.attrs["type"] == "poll")
		#expect(stanza.firstChild(named: "meta")?.attrs["polltype"] == pollType)
		#expect(stanza.firstChild(named: "enc")?.attrs["decrypt-fail"] == "hide")
	}

	@Test("a resent text message carries no extra nodes")
	func resentTextHasNoMeta() async throws {
		let client = WhatsAppClient(transportFactory: { _ in MockMessageSendWebSocketTransport() })
		var message = Proto_Message()
		message.conversation = "hi"
		await client.cacheRecentSentMessage(destinationJID: "123@s.whatsapp.net", id: "3EB0TEXT", message: message)

		let source = try #require(await client.retrySource(requestedDestinationJID: "123@s.whatsapp.net", id: "3EB0TEXT"))
		#expect(source.message.metaNodes.isEmpty)
	}

	@Test("resends a peer request to our phone as a peer request when its retry names no recipient")
	func resendsPeerRequestToOwnPhone() async throws {
		let (client, transport, encryptor) = try await peerRetryClient()
		try await sendPeerRequest(with: client)

		await client.handleIncomingNode(peerRetryReceipt(from: "999@s.whatsapp.net"))

		let stanza = try await resentMessageStanza(from: transport)
		#expect(stanza.attrs["id"] == "3EB0PEER")
		#expect(stanza.attrs["to"] == "999@s.whatsapp.net")
		#expect(stanza.attrs["recipient"] == nil)
		#expect(stanza.attrs["category"] == "peer")
		#expect(stanza.attrs["push_priority"] == "high_force")
		#expect(stanza.firstChild(named: "meta")?.attrs["appdata"] == "default")
		#expect(stanza.firstChild(named: "enc")?.attrs["count"] == "1")

		// Read as a request, not wrapped as the copy of a sent message.
		let payload = try #require(await encryptor.lastPayload)
		let message = try Proto_Message(serializedBytes: payload.dropLast())
		#expect(message.protocolMessage.type == .appStateSyncKeyRequest)
		#expect(!message.hasDeviceSentMessage)
		// Only the phone can answer: the other device is left out.
		#expect(await encryptor.jids == ["999@s.whatsapp.net", "999@s.whatsapp.net"])
	}

	@Test("finds a peer request sent by phone number when the phone retries by LID")
	func findsPeerRequestWhenPhoneRetriesByLID() async throws {
		let (client, transport, _) = try await peerRetryClient()
		try await sendPeerRequest(with: client)

		await client.handleIncomingNode(peerRetryReceipt(from: "888@lid"))

		let stanza = try await resentMessageStanza(from: transport)
		#expect(stanza.attrs["id"] == "3EB0PEER")
		#expect(stanza.attrs["to"] == "888@lid")
		#expect(stanza.attrs["category"] == "peer")
	}

	@Test("still fails a retry from our phone about a message that is not a known peer request")
	func failsRetryFromOwnPhoneAboutUnknownMessage() async throws {
		let (client, _, _) = try await peerRetryClient()
		try await sendPeerRequest(with: client)

		await #expect(throws: WhatsAppClientError.missingMessageDestination) {
			try await client.resendCachedMessages(for: MessageRetryRequest(
				key: WhatsAppMessageKey(remoteJID: nil, fromMe: true, id: "3EB0OTHER", participant: nil),
				messageIDs: ["3EB0OTHER"],
				requesterJID: "999@s.whatsapp.net",
				retryCount: 1
			))
		}
	}

	@Test("injects retry session bundles before resending cached messages")
	func injectsRetrySessionBundlesBeforeResendingCachedMessages() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let sessionInjector = RetrySessionInjector(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(
			results: [
				EncryptedMessage(type: "msg", ciphertext: Data([0x10])),
				EncryptedMessage(type: "msg", ciphertext: Data([0x20]))
			],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: sessionPreparer,
			retrySessionInjector: sessionInjector,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()
		_ = try await client.sendTextMessage(to: "123@s.whatsapp.net", text: "cached", messageID: "3EB0BUNDLE")

		_ = try await client.resendCachedMessage(for: MessageRetryRequest(
			key: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: true,
				id: "3EB0BUNDLE",
				participant: "123:2@s.whatsapp.net"
			),
			messageIDs: ["3EB0BUNDLE"],
			requesterJID: "123:2@s.whatsapp.net",
			retryCount: 3,
			sessionBundle: MessageRetrySessionBundle(
				registrationID: 9,
				identityKey: Data([0x05]) + Data(repeating: 0x11, count: 32),
				signedPreKey: SignalPreKey(
					keyID: 8,
					publicKey: Data([0x05]) + Data(repeating: 0x33, count: 32),
					signature: Data(repeating: 0x44, count: 64)
				),
				preKey: SignalPreKey(
					keyID: 7,
					publicKey: Data([0x05]) + Data(repeating: 0x22, count: 32)
				)
			)
		))

		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		#expect(await sessionInjector.bundles == [
			SignalSessionBundle(
				jid: "123:2@s.whatsapp.net",
				registrationID: 9,
				identityKey: Data([0x05]) + Data(repeating: 0x11, count: 32),
				signedPreKey: SignalPreKey(
					keyID: 8,
					publicKey: Data([0x05]) + Data(repeating: 0x33, count: 32),
					signature: Data(repeating: 0x44, count: 64)
				),
				preKey: SignalPreKey(
					keyID: 7,
					publicKey: Data([0x05]) + Data(repeating: 0x22, count: 32)
				)
			)
		])
		#expect(await callOrder.values == [
			"sessions",
			"encrypt:123.0@s.whatsapp.net",
			"inject:123:2@s.whatsapp.net",
			"encrypt:123:2@s.whatsapp.net"
		])
	}

	@Test("configured message dependencies wire retry session injection")
	func configuredMessageDependenciesWireRetrySessionInjection() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionInjector = RetrySessionInjector(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(
			results: [
				EncryptedMessage(type: "msg", ciphertext: Data([0x10])),
				EncryptedMessage(type: "msg", ciphertext: Data([0x20]))
			],
			callOrder: callOrder
		)
		let client = WhatsAppClient(transportFactory: { _ in transport })
		await client.configureMessageDependencies(WhatsAppClientMessageDependencies(
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			retrySessionInjector: sessionInjector
		))
		try await client.connect()
		_ = try await client.sendTextMessage(to: "123@s.whatsapp.net", text: "cached", messageID: "3EB0CONFIG")

		_ = try await client.resendCachedMessage(for: MessageRetryRequest(
			key: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: true,
				id: "3EB0CONFIG",
				participant: "123:2@s.whatsapp.net"
			),
			messageIDs: ["3EB0CONFIG"],
			requesterJID: "123:2@s.whatsapp.net",
			retryCount: 3,
			sessionBundle: MessageRetrySessionBundle(
				registrationID: 9,
				identityKey: Data([0x05]) + Data(repeating: 0x11, count: 32),
				signedPreKey: SignalPreKey(
					keyID: 8,
					publicKey: Data([0x05]) + Data(repeating: 0x33, count: 32),
					signature: Data(repeating: 0x44, count: 64)
				),
				preKey: SignalPreKey(
					keyID: 7,
					publicKey: Data([0x05]) + Data(repeating: 0x22, count: 32)
				)
			)
		))

		#expect(await sessionInjector.bundles.map(\.jid) == ["123:2@s.whatsapp.net"])
		#expect(await callOrder.values == [
			"sessions",
			"encrypt:123.0@s.whatsapp.net",
			"inject:123:2@s.whatsapp.net",
			"encrypt:123:2@s.whatsapp.net"
		])
	}

	@Test("skips invalid retry session bundles before resending cached messages")
	func skipsInvalidRetrySessionBundlesBeforeResendingCachedMessages() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let sessionInjector = RetrySessionInjector(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(
			results: [
				EncryptedMessage(type: "msg", ciphertext: Data([0x10])),
				EncryptedMessage(type: "msg", ciphertext: Data([0x20]))
			],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: sessionPreparer,
			retrySessionInjector: sessionInjector,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()
		_ = try await client.sendTextMessage(to: "123@s.whatsapp.net", text: "cached", messageID: "3EB0BADBUNDLE")

		_ = try await client.resendCachedMessage(for: MessageRetryRequest(
			key: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: true,
				id: "3EB0BADBUNDLE",
				participant: "123:2@s.whatsapp.net"
			),
			messageIDs: ["3EB0BADBUNDLE"],
			requesterJID: "123:2@s.whatsapp.net",
			retryCount: 3,
			sessionBundle: MessageRetrySessionBundle(
				registrationID: 9,
				identityKey: Data([0x05]) + Data(repeating: 0x11, count: 32),
				signedPreKey: SignalPreKey(
					keyID: 8,
					publicKey: Data([0x05]) + Data(repeating: 0x33, count: 32),
					signature: Data(repeating: 0x44, count: 64)
				),
				preKey: SignalPreKey(keyID: 7, publicKey: Data([0x04]) + Data(repeating: 0x22, count: 32))
			)
		))

		#expect(await sessionInjector.bundles.isEmpty)
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false),
			SignalSessionPreparationCall(jids: ["123:2@s.whatsapp.net"], force: true)
		])
		#expect(await callOrder.values == [
			"sessions",
			"encrypt:123.0@s.whatsapp.net",
			"sessions",
			"encrypt:123:2@s.whatsapp.net"
		])
	}

	@Test("resends every cached message id requested by retry receipts")
	func resendsEveryCachedMessageIDRequestedByRetryReceipts() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(
			results: [
				EncryptedMessage(type: "msg", ciphertext: Data([0x10])),
				EncryptedMessage(type: "msg", ciphertext: Data([0x11])),
				EncryptedMessage(type: "msg", ciphertext: Data([0x21])),
				EncryptedMessage(type: "msg", ciphertext: Data([0x22]))
			],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: sessionPreparer,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()
		_ = try await client.sendTextMessage(to: "123@s.whatsapp.net", text: "first", messageID: "3EB0BATCH1")
		_ = try await client.sendTextMessage(to: "123@s.whatsapp.net", text: "second", messageID: "3EB0BATCH2")

		let resentIDs = try await client.resendCachedMessages(for: MessageRetryRequest(
			key: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: true,
				id: "3EB0BATCH1",
				participant: "123:2@s.whatsapp.net"
			),
			messageIDs: ["3EB0BATCH1", "3EB0BATCH2"],
			requesterJID: "123:2@s.whatsapp.net",
			retryCount: 2
		))

		#expect(resentIDs == ["3EB0BATCH1", "3EB0BATCH2"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false),
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false),
			SignalSessionPreparationCall(jids: ["123:2@s.whatsapp.net"], force: true)
		])

		let stanzas = try await retryResendStanzas(from: transport, startingAt: 2, count: 2)
		#expect(stanzas.map { $0.attrs["id"] } == ["3EB0BATCH1", "3EB0BATCH2"])
		#expect(stanzas.map { $0.attrs["to"] } == ["123:2@s.whatsapp.net", "123:2@s.whatsapp.net"])
		#expect(stanzas.map { $0.firstChild(named: "enc")?.content } == [
			.data(Data([0x21])),
			.data(Data([0x22]))
		])
		#expect(stanzas.map { $0.firstChild(named: "enc")?.attrs["count"] } == ["2", "2"])
	}

	@Test("resolves participant devices for group retry requests without a device suffix")
	func resolvesParticipantDevicesForGroupRetryRequestsWithoutADeviceSuffix() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let deviceResolver = StubMessageDeviceResolver(result: ["456.0@s.whatsapp.net"])
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: StubMessageSendEncryptor(results: [
				EncryptedMessage(type: "msg", ciphertext: Data([0x20]))
			], callOrder: callOrder),
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: sessionPreparer,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()
		var cachedMessage = Proto_Message()
		cachedMessage.conversation = "cached group"
		await client.cacheRecentSentMessage(
			destinationJID: "123@g.us",
			id: "3EB0GROUPRETRY",
			message: cachedMessage
		)

		let resentIDs = try await client.resendCachedMessages(for: MessageRetryRequest(
			key: WhatsAppMessageKey(remoteJID: "123@g.us", fromMe: true, id: "3EB0GROUPRETRY"),
			messageIDs: ["3EB0GROUPRETRY"],
			requesterJID: "456@s.whatsapp.net",
			retryCount: 2
		))

		#expect(resentIDs == ["3EB0GROUPRETRY"])
		#expect(await deviceResolver.calls == ["456@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["456.0@s.whatsapp.net"], force: true)
		])

		let stanza = try await retryResendStanzas(from: transport, startingAt: 0, count: 1)[0]
		#expect(stanza.attrs["id"] == "3EB0GROUPRETRY")
		#expect(stanza.attrs["to"] == "123@g.us")
		#expect(stanza.attrs["participant"] == "456.0@s.whatsapp.net")
		#expect(stanza.firstChild(named: "enc")?.content == .data(Data([0x20])))
	}

	@Test("does not count a group retry as resent when requester device resolution is empty")
	func doesNotCountGroupRetryAsResentWhenRequesterDeviceResolutionIsEmpty() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let deviceResolver = StubMessageDeviceResolver(result: [])
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: StubMessageSendEncryptor(results: [], callOrder: callOrder),
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder)
		)
		try await client.connect()
		var cachedMessage = Proto_Message()
		cachedMessage.conversation = "cached group"
		await client.cacheRecentSentMessage(
			destinationJID: "123@g.us",
			id: "3EB0EMPTYDEVICES",
			message: cachedMessage
		)

		let resentIDs = try await client.resendCachedMessages(for: MessageRetryRequest(
			key: WhatsAppMessageKey(remoteJID: "123@g.us", fromMe: true, id: "3EB0EMPTYDEVICES"),
			messageIDs: ["3EB0EMPTYDEVICES"],
			requesterJID: "456@s.whatsapp.net",
			retryCount: 2
		))

		#expect(resentIDs == [])
		#expect(await transport.sentFrames.isEmpty)
		#expect(await deviceResolver.calls == ["456@s.whatsapp.net"])
	}
}

private func peerRetryClient() async throws -> (WhatsAppClient, MockMessageSendWebSocketTransport, PeerRecordingEncryptor) {
	let transport = MockMessageSendWebSocketTransport()
	let encryptor = PeerRecordingEncryptor()
	let client = WhatsAppClient(
		authenticationState: AuthenticationState(
			credentials: sampleMessageSendCredentials(me: WhatsAppUser(id: "999:21@s.whatsapp.net", lid: "888:21@lid")),
			keys: InMemorySignalKeyStore(storage: [:])
		),
		transportFactory: { _ in transport },
		messageEncryptor: encryptor,
		messageDeviceResolver: OwnPhoneDeviceResolver(),
		signalSessionPreparer: StubSignalSessionPreparer(callOrder: MessageSendCallOrder()),
		messageEncoder: MessageEncoder(randomByte: { 0x00 })
	)
	try await client.connect()
	return (client, transport, encryptor)
}

private func sendPeerRequest(with client: WhatsAppClient) async throws {
	var protocolMessage = Proto_Message.ProtocolMessageMessage()
	protocolMessage.type = .appStateSyncKeyRequest
	var message = Proto_Message()
	message.protocolMessage = protocolMessage
	_ = try await client.sendDirectMessage(
		to: "999@s.whatsapp.net",
		message: message,
		recipientDeviceJIDs: ["999@s.whatsapp.net"],
		messageID: "3EB0PEER",
		additionalAttributes: ["category": "peer", "push_priority": "high_force"],
		additionalNodes: [BinaryNode(tag: "meta", attrs: ["appdata": "default"])]
	)
}

private func peerRetryReceipt(from jid: String) -> BinaryNode {
	BinaryNode(
		tag: "receipt",
		attrs: ["from": jid, "id": "3EB0PEER", "type": "retry", "t": "1700000003"],
		content: .nodes([BinaryNode(tag: "retry", attrs: ["count": "1"])])
	)
}

/// The second message stanza to go out, after the original send.
private func resentMessageStanza(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	for _ in 0..<2000 {
		let stanzas = try await transport.sentFrames.map { frame -> BinaryNode in
			var codec = NoiseFrameCodec()
			return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
		}.filter { $0.tag == "message" }
		if stanzas.count >= 2 {
			return stanzas[1]
		}
		try await Task.sleep(for: .milliseconds(1))
	}
	throw WhatsAppClientError.missingRetryMessage
}

private struct OwnPhoneDeviceResolver: MessageDeviceResolving {
	func deviceJIDs(for jid: String) async throws -> [String] {
		jid.hasSuffix("@lid")
			? ["888@lid", "888:5@lid", "888:21@lid"]
			: ["999@s.whatsapp.net", "999:5@s.whatsapp.net", "999:21@s.whatsapp.net"]
	}
}

private actor PeerRecordingEncryptor: MessageEncrypting {
	private(set) var jids: [String] = []
	private(set) var lastPayload: Data?

	func encryptMessage(jid: String, data: Data) async throws -> EncryptedMessage {
		jids.append(jid)
		lastPayload = data
		return EncryptedMessage(type: "msg", ciphertext: Data([0x01]))
	}
}

private func retryResendStanza(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	while await transport.sentFrames.count < 2 {
		try await Task.sleep(for: .milliseconds(1))
	}

	let frame = await transport.sentFrames[1]
	var codec = NoiseFrameCodec()
	return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
}

private func retryResendStanzas(
	from transport: MockMessageSendWebSocketTransport,
	startingAt index: Int,
	count: Int
) async throws -> [BinaryNode] {
	while await transport.sentFrames.count < index + count {
		try await Task.sleep(for: .milliseconds(1))
	}

	let frames = await Array(transport.sentFrames[index..<(index + count)])
	return try frames.map { frame in
		var codec = NoiseFrameCodec()
		return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
	}
}

private actor RetrySessionInjector: SignalSessionInjecting {
	private let callOrder: MessageSendCallOrder
	private(set) var bundles: [SignalSessionBundle] = []

	init(callOrder: MessageSendCallOrder) {
		self.callOrder = callOrder
	}

	func injectSession(bundle: SignalSessionBundle) async throws {
		await callOrder.append("inject:\(bundle.jid)")
		bundles.append(bundle)
	}
}
