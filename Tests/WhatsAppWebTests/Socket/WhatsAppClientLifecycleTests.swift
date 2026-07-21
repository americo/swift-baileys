import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client lifecycle")
struct WhatsAppClientLifecycleTests {
	@Test("connects through the configured WebSocket transport")
	func connectsThroughConfiguredTransport() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(
			configuration: WhatsAppClientConfiguration(webSocketURL: URL(string: "wss://example.test/ws")!),
			transportFactory: { url in
				#expect(url.absoluteString == "wss://example.test/ws")
				return transport
			}
		)

		try await client.connect()

		#expect(await transport.connectCount == 1)
		#expect(await client.state == .connected)
	}

	@Test("sends raw frames through the connected transport")
	func sendsRawFrames() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		try await client.sendRawFrame(Data([1, 2, 3]))

		#expect(await transport.sentFrames == [Data([1, 2, 3])])
	}

	@Test("sending before connect fails explicitly")
	func sendingBeforeConnectFails() async {
		let client = WhatsAppClient(transportFactory: { _ in MockWebSocketTransport() })

		await #expect(throws: WhatsAppClientError.notConnected) {
			try await client.sendRawFrame(Data([1]))
		}
	}

	@Test("connect failure restores disconnected state")
	func connectFailureRestoresDisconnectedState() async {
		let transport = MockWebSocketTransport()
		await transport.setConnectError(MockReceiveError.broken)
		let client = WhatsAppClient(transportFactory: { _ in transport })

		await #expect(throws: MockReceiveError.broken) {
			try await client.connect()
		}
		#expect(await client.state == .disconnected)
		#expect(await transport.closeCount == 1)
	}

	@Test("updates authentication credentials through the client")
	func updatesAuthenticationCredentialsThroughClient() async throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("swift-baileys-client-auth-\(UUID().uuidString)", isDirectory: true)
		let store = FileAuthenticationStore(directory: directory)
		let authState = try await AuthenticationState.loadOrCreate(
			store: store,
			credentialsFactory: { sampleCredentials(registrationID: 555) }
		)
		let client = WhatsAppClient(authenticationState: authState, transportFactory: { _ in MockWebSocketTransport() })
		var events = client.events.makeAsyncIterator()

		try await client.updateCredentials { credentials in
			credentials.registered = true
			credentials.me = WhatsAppUser(id: "123@s.whatsapp.net")
		}

		let credentials = await client.authenticationState?.credentials
		#expect(credentials?.registered == true)
		#expect(credentials?.me == WhatsAppUser(id: "123@s.whatsapp.net"))
		#expect(try await store.loadCredentials() == credentials)
		#expect(await events.next() == .credentialsUpdated(credentials!))
	}

	@Test("emits QR code data from pair-device refs")
	func emitsQRCodeDataFromPairDeviceRefs() async throws {
		let authState = AuthenticationState(
			credentials: sampleCredentials(registrationID: 556),
			keys: InMemorySignalKeyStore()
		)
		let client = WhatsAppClient(authenticationState: authState, transportFactory: { _ in MockWebSocketTransport() })
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(
			BinaryNode(
				tag: "iq",
				attrs: ["id": "pair-1", "type": "set"],
				content: .nodes([
					BinaryNode(
						tag: "pair-device",
						content: .nodes([
							BinaryNode(tag: "ref", content: .data(Data("ref-one".utf8)))
						])
					)
				])
			)
		)

		#expect(await events.next() == .qrCode("https://wa.me/settings/linked_devices#ref-one,Ag==,Bg==,adv-secret,7"))
	}

	@Test("acknowledges pair-device iq before emitting QR")
	func acknowledgesPairDeviceIQBeforeEmittingQR() async throws {
		let transport = MockWebSocketTransport()
		let authState = AuthenticationState(
			credentials: sampleCredentials(registrationID: 557),
			keys: InMemorySignalKeyStore()
		)
		let client = WhatsAppClient(authenticationState: authState, transportFactory: { _ in transport })
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(
			BinaryNode(
				tag: "iq",
				attrs: ["id": "pair-ack-1", "type": "set"],
				content: .nodes([
					BinaryNode(
						tag: "pair-device",
						content: .nodes([
							BinaryNode(tag: "ref", content: .string("ref-two"))
						])
					)
				])
			)
		)

		let sentTransportFrames = await transport.sentFrames
		#expect(sentTransportFrames.count == 1)
		if let sentTransportFrame = sentTransportFrames.first {
			var codec = NoiseFrameCodec()
			let sentFrames = codec.decode(sentTransportFrame)
			let ack = try BinaryNodeDecoder().decode(sentFrames[0])
			#expect(ack == BinaryNode(tag: "iq", attrs: ["to": "@s.whatsapp.net", "type": "result", "id": "pair-ack-1"]))
		}
		#expect(await events.next() == .qrCode("https://wa.me/settings/linked_devices#ref-two,Ag==,Bg==,adv-secret,7"))
	}

	@Test("processes pair-success through the configured processor")
	func processesPairSuccessThroughConfiguredProcessor() async throws {
		let transport = MockWebSocketTransport()
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("swift-baileys-pair-success-\(UUID().uuidString)", isDirectory: true)
		let store = FileAuthenticationStore(directory: directory)
		let authState = try await AuthenticationState.loadOrCreate(
			store: store,
			credentialsFactory: { sampleCredentials(registrationID: 558) }
		)
		let reply = BinaryNode(tag: "iq", attrs: ["to": "@s.whatsapp.net", "type": "result", "id": "pair-success-1"])
		let processor = StubPairSuccessProcessor(result: PairSuccessProcessingResult(reply: reply) { credentials in
			credentials.registered = true
			credentials.me = WhatsAppUser(id: "123@s.whatsapp.net", name: "Paired")
		})
		let client = WhatsAppClient(
			authenticationState: authState,
			pairSuccessProcessor: processor,
			transportFactory: { _ in transport }
		)
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(
			BinaryNode(
				tag: "iq",
				attrs: ["id": "pair-success-1"],
				content: .nodes([BinaryNode(tag: "pair-success")])
			)
		)

		let credentials = await client.authenticationState?.credentials
		#expect(credentials?.registered == true)
		#expect(credentials?.me == WhatsAppUser(id: "123@s.whatsapp.net", name: "Paired"))
		#expect(try await store.loadCredentials() == credentials)
		#expect(processor.receivedStanza?.attrs["id"] == "pair-success-1")
		#expect(await events.next() == .credentialsUpdated(credentials!))
		#expect(await events.next() == .newLogin)

		var codec = NoiseFrameCodec()
		let sentFrames = codec.decode(await transport.sentFrames[0])
		#expect(try BinaryNodeDecoder().decode(sentFrames[0]) == reply)
	}

	@Test("query sends a binary node and resolves the matching response")
	func querySendsNodeAndResolvesResponse() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.query(
				BinaryNode(tag: "iq", attrs: ["id": "query-1", "type": "get"]),
				timeout: .seconds(1)
			)
		}

		while await transport.sentFrames.isEmpty {
			try await Task.sleep(for: .milliseconds(1))
		}

		var codec = NoiseFrameCodec()
		let sentFrames = codec.decode(await transport.sentFrames[0])
		#expect(sentFrames.count == 1)
		let sentNode = try BinaryNodeDecoder().decode(sentFrames[0])
		#expect(sentNode.attrs["id"] == "query-1")

		await client.handleIncomingNode(BinaryNode(tag: "iq", attrs: ["id": "query-1", "type": "result"]))

		let response = try await task.value
		#expect(response.attrs["type"] == "result")
	}

	@Test("query frames the encoded binary node before sending")
	func queryFramesEncodedBinaryNodeBeforeSending() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		let node = BinaryNode(tag: "iq", attrs: ["id": "framed-query", "type": "get"])
		let encodedNode = try BinaryNodeEncoder().encode(node)
		try await client.connect()

		let task = Task {
			try await client.query(node, timeout: .seconds(1))
		}

		while await transport.sentFrames.isEmpty {
			try await Task.sleep(for: .milliseconds(1))
		}

		let sentFrame = await transport.sentFrames[0]
		#expect(sentFrame.prefix(3) == Data([0, 0, UInt8(encodedNode.count)]))
		var codec = NoiseFrameCodec()
		#expect(codec.decode(sentFrame) == [encodedNode])

		await client.handleIncomingNode(BinaryNode(tag: "iq", attrs: ["id": "framed-query", "type": "result"]))
		_ = try await task.value
	}

	@Test("query throws server error responses")
	func queryThrowsServerErrorResponses() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.query(
				BinaryNode(tag: "iq", attrs: ["id": "error-query", "type": "get"]),
				timeout: .seconds(1)
			)
		}

		while await transport.sentFrames.isEmpty {
			try await Task.sleep(for: .milliseconds(1))
		}

		let errorNode = BinaryNode(tag: "error", attrs: ["code": "401", "text": "not-authorized"])
		await client.handleIncomingNode(BinaryNode(
			tag: "iq",
			attrs: ["id": "error-query", "type": "error"],
			content: .nodes([errorNode])
		))

		await #expect(throws: BinaryNodeServerError(message: "not-authorized", code: 401, node: errorNode)) {
			try await task.value
		}
	}

	@Test("query without a stanza id fails explicitly")
	func queryWithoutStanzaIDFails() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		await #expect(throws: WhatsAppClientError.missingRequestID) {
			try await client.query(BinaryNode(tag: "iq", attrs: ["type": "get"]))
		}
	}

	@Test("query with an empty stanza id fails explicitly")
	func queryWithEmptyStanzaIDFails() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		await #expect(throws: WhatsAppClientError.emptyRequestID) {
			try await client.query(BinaryNode(tag: "iq", attrs: ["id": "", "type": "get"]))
		}
		#expect(await transport.sentFrames.isEmpty)
	}

	@Test("sends prepared direct text messages through relay builder")
	func sendsPreparedDirectTextMessagesThroughRelayBuilder() async throws {
		let transport = MockWebSocketTransport()
		let encryptor = StubMessageEncryptor(
			results: [
				EncryptedMessage(type: "msg", ciphertext: Data([0xca, 0xfe]))
			]
		)
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		let messageID = try await client.sendDirectTextMessage(
			to: "123@s.whatsapp.net",
			text: "hello from swift",
			recipientDeviceJIDs: ["123.0@s.whatsapp.net"],
			messageID: "3EB0TEXTMESSAGE"
		)

		#expect(messageID == "3EB0TEXTMESSAGE")
		#expect(await encryptor.calls == [
			MessageEncryptionCall(
				jid: "123.0@s.whatsapp.net",
				data: try MessageEncoder(randomByte: { 0x00 }).encode(MessageContentBuilder.text("hello from swift"))
			)
		])
		var codec = NoiseFrameCodec()
		let sentFrames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(sentFrames[0])
		#expect(
			stanza == BinaryNode(
				tag: "message",
				attrs: ["id": "3EB0TEXTMESSAGE", "to": "123@s.whatsapp.net", "type": "text", "phash": "2:b8aCUh"],
				content: .nodes([
					BinaryNode(
						tag: "participants",
						content: .nodes([
							BinaryNode(
								tag: "to",
								attrs: ["jid": "123.0@s.whatsapp.net"],
								content: .nodes([
									BinaryNode(tag: "enc", attrs: ["v": "2", "type": "msg"], content: .data(Data([0xca, 0xfe])))
								])
							)
						])
					)
				])
			)
		)
	}

	@Test("receive loop decodes binary nodes into message events")
	func receiveLoopDecodesBinaryNodes() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		var events = client.events.makeAsyncIterator()
		let node = BinaryNode(tag: "message", attrs: ["id": "msg-1"], content: .string("hello"))
		let expectedNode = try BinaryNodeDecoder().decode(BinaryNodeEncoder().encode(node))
		var codec = NoiseFrameCodec()

		try await client.connect()
		await transport.enqueueInbound(codec.encode(try BinaryNodeEncoder().encode(node)))

		#expect(await events.next() == .message(expectedNode))
	}

	@Test("emits parsed received messages when a message decryptor is configured")
	func emitsParsedReceivedMessagesWhenDecryptorConfigured() async throws {
		let transport = MockWebSocketTransport()
		let incomingMessage = MessageContentBuilder.text("hello from inbound")
		let decryptor = StubIncomingMessageDecryptor(result: incomingMessage)
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageDecryptor: decryptor
		)
		var events = client.events.makeAsyncIterator()
		let node = BinaryNode(
			tag: "message",
			attrs: ["id": "msg-inbound-1", "from": "123@s.whatsapp.net", "t": "1700000000"],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0x01, 0x02])))
			])
		)
		let expectedNode = try BinaryNodeDecoder().decode(BinaryNodeEncoder().encode(node))
		var codec = NoiseFrameCodec()

		try await client.connect()
		await transport.enqueueInbound(codec.encode(try BinaryNodeEncoder().encode(node)))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "msg-inbound-1",
			from: "123@s.whatsapp.net",
			timestamp: 1_700_000_000,
			content: .text("hello from inbound")
		)))
		#expect(await decryptor.calls == [expectedNode])
	}

	@Test("receive loop resolves pending query responses")
	func receiveLoopResolvesPendingQueryResponses() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		var codec = NoiseFrameCodec()
		try await client.connect()

		let task = Task {
			try await client.query(
				BinaryNode(tag: "iq", attrs: ["id": "rx-query", "type": "get"]),
				timeout: .seconds(1)
			)
		}

		while await transport.sentFrames.isEmpty {
			try await Task.sleep(for: .milliseconds(1))
		}

		let response = BinaryNode(tag: "iq", attrs: ["id": "rx-query", "type": "result"])
		await transport.enqueueInbound(codec.encode(try BinaryNodeEncoder().encode(response)))

		#expect(try await task.value == response)
	}

	@Test("receive loop emits disconnected when transport closes")
	func receiveLoopEmitsDisconnectedWhenTransportCloses() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		var events = client.events.makeAsyncIterator()

		try await client.connect()
		await transport.enqueueInboundClose()

		#expect(await events.next() == .disconnected(reason: "Connection Closed"))
		#expect(await client.state == .disconnected)
		#expect(await transport.closeCount == 1)
	}

	@Test("receive loop emits disconnected when receive fails")
	func receiveLoopEmitsDisconnectedWhenReceiveFails() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		var events = client.events.makeAsyncIterator()

		try await client.connect()
		await transport.enqueueInboundError(MockReceiveError.broken)

		#expect(await events.next() == .disconnected(reason: "Receive Loop Error (broken)"))
		#expect(await client.state == .disconnected)
		#expect(await transport.closeCount == 1)
	}

	@Test("stream error closes the client")
	func streamErrorClosesClient() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "stream:error",
			content: .nodes([BinaryNode(tag: "conflict")])
		))

		#expect(await transport.closeCount == 1)
		#expect(await client.state == .disconnected)
		#expect(await events.next() == .disconnected(reason: "Stream Errored (conflict)"))
	}

	@Test("failure node closes the client")
	func failureNodeClosesClient() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(tag: "failure", attrs: ["reason": "401"]))

		#expect(await transport.closeCount == 1)
		#expect(await client.state == .disconnected)
		#expect(await events.next() == .disconnected(reason: "Connection Failure (401)"))
	}

	@Test("xml stream end closes the client")
	func xmlStreamEndClosesClient() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(tag: "xmlstreamend"))

		#expect(await transport.closeCount == 1)
		#expect(await client.state == .disconnected)
		#expect(await events.next() == .disconnected(reason: "Connection Terminated by Server"))
	}

	@Test("disconnect closes the transport and emits a disconnected event")
	func disconnectClosesTransport() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		var events = client.events.makeAsyncIterator()

		try await client.connect()
		await client.disconnect(reason: "test-close")

		#expect(await transport.closeCount == 1)
		#expect(await client.state == .disconnected)
		#expect(await events.next() == .disconnected(reason: "test-close"))
	}

	private func sampleCredentials(registrationID: Int) -> AuthenticationCredentials {
		AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data([6])),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([8])),
				signature: Data([9]),
				keyID: 1
			),
			registrationID: registrationID,
			advSecretKey: "adv-secret",
			nextPreKeyID: 1,
			firstUnuploadedPreKeyID: 1,
			accountSyncCounter: 0,
			registered: false
		)
	}
}

private final class StubPairSuccessProcessor: PairSuccessProcessing, @unchecked Sendable {
	let result: PairSuccessProcessingResult
	private let lock = NSLock()
	private var stanza: BinaryNode?

	init(result: PairSuccessProcessingResult) {
		self.result = result
	}

	var receivedStanza: BinaryNode? {
		lock.withLock {
			stanza
		}
	}

	func processPairSuccess(stanza: BinaryNode, credentials: AuthenticationCredentials) throws -> PairSuccessProcessingResult {
		lock.withLock {
			self.stanza = stanza
		}
		return result
	}
}

private actor StubMessageEncryptor: MessageEncrypting {
	private let results: [EncryptedMessage]
	private var nextResultIndex = 0
	private(set) var calls: [MessageEncryptionCall] = []

	init(results: [EncryptedMessage]) {
		self.results = results
	}

	func encryptMessage(jid: String, data: Data) async throws -> EncryptedMessage {
		calls.append(MessageEncryptionCall(jid: jid, data: data))
		let result = results[nextResultIndex]
		nextResultIndex += 1
		return result
	}
}

private struct MessageEncryptionCall: Equatable, Sendable {
	let jid: String
	let data: Data
}

private actor StubIncomingMessageDecryptor: IncomingMessageDecrypting {
	private let result: Proto_Message?
	private(set) var calls: [BinaryNode] = []

	init(result: Proto_Message?) {
		self.result = result
	}

	func decryptIncomingMessage(from node: BinaryNode) async throws -> Proto_Message? {
		calls.append(node)
		return result
	}
}
