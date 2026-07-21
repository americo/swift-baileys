import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client incoming receipts")
struct WhatsAppClientIncomingReceiptTests {
	@Test("emits message status updates from direct receipts")
	func emitsMessageStatusUpdatesFromDirectReceipts() async throws {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "receipt",
			attrs: ["from": "123@s.whatsapp.net", "id": "msg-1", "type": "read", "t": "1700000000"],
			content: .nodes([
				BinaryNode(tag: "list", content: .nodes([
					BinaryNode(tag: "item", attrs: ["id": "msg-2"])
				]))
			])
		))

		#expect(await events.next() == .messagesUpdated([
			ReceivedMessageUpdate(
				key: WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: true, id: "msg-1"),
				status: .read,
				timestamp: 1_700_000_000
			),
			ReceivedMessageUpdate(
				key: WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: true, id: "msg-2"),
				status: .read,
				timestamp: 1_700_000_000
			)
		]))
	}

	@Test("emits participant receipt updates from group receipts")
	func emitsParticipantReceiptUpdatesFromGroupReceipts() async throws {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "receipt",
			attrs: [
				"from": "123@g.us",
				"id": "group-msg-1",
				"participant": "456:17@s.whatsapp.net",
				"t": "1700000001"
			]
		))

		#expect(await events.next() == .messageReceiptsUpdated([
			ReceivedMessageReceiptUpdate(
				key: WhatsAppMessageKey(
					remoteJID: "123@g.us",
					fromMe: true,
					id: "group-msg-1",
					participant: "456:17@s.whatsapp.net"
				),
				receipt: ReceivedMessageUserReceipt(
					userJID: "456@s.whatsapp.net",
					receiptTimestamp: 1_700_000_001,
					readTimestamp: nil
				)
			)
		]))
	}

	@Test("acknowledges processed receipt stanzas")
	func acknowledgesProcessedReceiptStanzas() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "receipt",
			attrs: [
				"from": "123@s.whatsapp.net",
				"id": "msg-ack-1",
				"recipient": "999@s.whatsapp.net",
				"participant": "456@s.whatsapp.net",
				"type": "read"
			]
		))

		let ack = try await firstReceiptAck(from: transport)
		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: [
				"id": "msg-ack-1",
				"to": "123@s.whatsapp.net",
				"class": "receipt",
				"participant": "456@s.whatsapp.net",
				"recipient": "999@s.whatsapp.net",
				"type": "read"
			]
		))
	}

	@Test("acknowledges and drops receipts filtered by configuration")
	func acknowledgesAndDropsReceiptsFilteredByConfiguration() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(
			configuration: WhatsAppClientConfiguration(shouldIgnoreJID: { $0 == "123@s.whatsapp.net" }),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "receipt",
			attrs: ["from": "123@s.whatsapp.net", "id": "ignored-receipt-1", "type": "read"]
		))

		let ack = try await firstReceiptAck(from: transport)
		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: [
				"id": "ignored-receipt-1",
				"to": "123@s.whatsapp.net",
				"class": "receipt",
				"type": "read"
			]
		))
	}

	@Test("emits retry requests from retry receipts")
	func emitsRetryRequestsFromRetryReceipts() async throws {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "receipt",
			attrs: [
				"from": "123@s.whatsapp.net",
				"id": "retry-msg-1",
				"type": "retry",
				"participant": "123:2@s.whatsapp.net",
				"t": "1700000002"
			],
			content: .nodes([
				BinaryNode(tag: "retry", attrs: ["count": "2"]),
				BinaryNode(tag: "list", content: .nodes([
					BinaryNode(tag: "item", attrs: ["id": "retry-msg-2"])
				]))
			])
		))

		#expect(await events.next() == .messageRetryRequested(MessageRetryRequest(
			key: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: true,
				id: "retry-msg-1",
				participant: "123:2@s.whatsapp.net"
			),
			messageIDs: ["retry-msg-1", "retry-msg-2"],
			requesterJID: "123:2@s.whatsapp.net",
			retryCount: 2,
			timestamp: 1_700_000_002
		)))
	}

	@Test("emits retry resend failures when automatic resend cannot run")
	func emitsRetryResendFailuresWhenAutomaticResendCannotRun() async throws {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "receipt",
			attrs: [
				"from": "123@s.whatsapp.net",
				"id": "retry-fail-1",
				"type": "retry",
				"participant": "123:2@s.whatsapp.net",
				"t": "1700000003"
			],
			content: .nodes([
				BinaryNode(tag: "retry", attrs: ["count": "2"])
			])
		))

		let request = MessageRetryRequest(
			key: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: true,
				id: "retry-fail-1",
				participant: "123:2@s.whatsapp.net"
			),
			messageIDs: ["retry-fail-1"],
			requesterJID: "123:2@s.whatsapp.net",
			retryCount: 2,
			timestamp: 1_700_000_003
		)
		#expect(await events.next() == .messageRetryRequested(request))
		#expect(await events.next() == .messageRetryResendFailed(MessageRetryResendFailure(
			request: request,
			reason: .missingDependency(.messageEncryptor)
		)))
	}

	@Test("acknowledges retry receipt stanzas")
	func acknowledgesRetryReceiptStanzas() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "receipt",
			attrs: [
				"from": "123@s.whatsapp.net",
				"id": "retry-msg-ack",
				"type": "retry",
				"participant": "123:2@s.whatsapp.net"
			],
			content: .nodes([
				BinaryNode(tag: "retry", attrs: ["count": "1"])
			])
		))

		let ack = try await firstReceiptAck(from: transport)
		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: [
				"id": "retry-msg-ack",
				"to": "123@s.whatsapp.net",
				"class": "receipt",
				"participant": "123:2@s.whatsapp.net",
				"type": "retry"
			]
		))
	}

	@Test("includes retry registration and session bundle details")
	func includesRetryRegistrationAndSessionBundleDetails() async throws {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "receipt",
			attrs: ["from": "123@s.whatsapp.net", "id": "retry-bundle-1", "type": "retry"],
			content: .nodes([
				BinaryNode(tag: "retry", attrs: ["count": "3"]),
				BinaryNode(tag: "registration", content: .data(Data([0, 0, 0, 9]))),
				BinaryNode(tag: "keys", content: .nodes([
					BinaryNode(tag: "type", content: .data(Data([0x05]))),
					BinaryNode(tag: "identity", content: .data(Data(repeating: 0x11, count: 32))),
					BinaryNode(tag: "key", content: .nodes([
						BinaryNode(tag: "id", content: .data(Data([0, 0, 7]))),
						BinaryNode(tag: "value", content: .data(Data(repeating: 0x22, count: 32)))
					])),
					BinaryNode(tag: "skey", content: .nodes([
						BinaryNode(tag: "id", content: .data(Data([0, 0, 8]))),
						BinaryNode(tag: "value", content: .data(Data(repeating: 0x33, count: 32))),
						BinaryNode(tag: "signature", content: .data(Data(repeating: 0x44, count: 64)))
					]))
				]))
			])
		))

		#expect(await events.next() == .messageRetryRequested(MessageRetryRequest(
			key: WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: true, id: "retry-bundle-1"),
			messageIDs: ["retry-bundle-1"],
			requesterJID: "123@s.whatsapp.net",
			retryCount: 3,
			timestamp: nil,
			requesterRegistrationID: 9,
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
		)))
	}

	@Test("omits retry session bundle when signed pre-key signature length is invalid")
	func omitsRetrySessionBundleWhenSignedPreKeySignatureLengthIsInvalid() async throws {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "receipt",
			attrs: ["from": "123@s.whatsapp.net", "id": "retry-bundle-short-sig", "type": "retry"],
			content: .nodes([
				BinaryNode(tag: "retry", attrs: ["count": "3"]),
				BinaryNode(tag: "registration", content: .data(Data([0, 0, 0, 9]))),
				BinaryNode(tag: "keys", content: .nodes([
					BinaryNode(tag: "type", content: .data(Data([0x05]))),
					BinaryNode(tag: "identity", content: .data(Data(repeating: 0x11, count: 32))),
					BinaryNode(tag: "key", content: .nodes([
						BinaryNode(tag: "id", content: .data(Data([0, 0, 7]))),
						BinaryNode(tag: "value", content: .data(Data(repeating: 0x22, count: 32)))
					])),
					BinaryNode(tag: "skey", content: .nodes([
						BinaryNode(tag: "id", content: .data(Data([0, 0, 8]))),
						BinaryNode(tag: "value", content: .data(Data(repeating: 0x33, count: 32))),
						BinaryNode(tag: "signature", content: .data(Data([0x44, 0x45])))
					]))
				]))
			])
		))

		let event = try #require(await events.next())
		if case .messageRetryRequested(let request) = event {
			#expect(request.requesterRegistrationID == 9)
			#expect(request.sessionBundle == nil)
		} else {
			Issue.record("expected message retry request")
		}
	}

	@Test("automatically resends cached messages for retry receipts")
	func automaticallyResendsCachedMessagesForRetryReceipts() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: StubMessageSendEncryptor(results: [
				EncryptedMessage(type: "msg", ciphertext: Data([0x10])),
				EncryptedMessage(type: "msg", ciphertext: Data([0x20]))
			], callOrder: callOrder),
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		var events = client.events.makeAsyncIterator()
		try await client.connect()
		_ = try await client.sendTextMessage(to: "123@s.whatsapp.net", text: "cached", messageID: "3EB0AUTORETRY")

		await client.handleIncomingNode(BinaryNode(
			tag: "receipt",
			attrs: [
				"from": "123@s.whatsapp.net",
				"id": "3EB0AUTORETRY",
				"type": "retry",
				"participant": "123:2@s.whatsapp.net"
			],
			content: .nodes([
				BinaryNode(tag: "retry", attrs: ["count": "2"])
			])
		))

		#expect(await events.next() == .messageRetryRequested(MessageRetryRequest(
			key: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: true,
				id: "3EB0AUTORETRY",
				participant: "123:2@s.whatsapp.net"
			),
			messageIDs: ["3EB0AUTORETRY"],
			requesterJID: "123:2@s.whatsapp.net",
			retryCount: 2
		)))

		let nodes = try await sentReceiptNodes(from: transport, count: 3)
		#expect(nodes.count == 3)
		#expect(nodes[1] == BinaryNode(
			tag: "ack",
			attrs: [
				"id": "3EB0AUTORETRY",
				"to": "123@s.whatsapp.net",
				"class": "receipt",
				"participant": "123:2@s.whatsapp.net",
				"type": "retry"
			]
		))
		let retryResend = try #require(nodes.count > 2 ? nodes[2] : nil)
		#expect(retryResend.attrs["id"] == "3EB0AUTORETRY")
		#expect(retryResend.attrs["to"] == "123:2@s.whatsapp.net")
		#expect(retryResend.firstChild(named: "enc")?.attrs["count"] == "2")
		#expect(retryResend.firstChild(named: "enc")?.content == .data(Data([0x20])))
	}

	@Test("stops automatic retry resend after the configured retry limit")
	func stopsAutomaticRetryResendAfterTheConfiguredRetryLimit() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let client = WhatsAppClient(
			configuration: WhatsAppClientConfiguration(maxMessageRetryCount: 1),
			transportFactory: { _ in transport },
			messageEncryptor: StubMessageSendEncryptor(results: [
				EncryptedMessage(type: "msg", ciphertext: Data([0x10])),
				EncryptedMessage(type: "msg", ciphertext: Data([0x20]))
			], callOrder: callOrder),
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()
		_ = try await client.sendTextMessage(to: "123@s.whatsapp.net", text: "cached", messageID: "3EB0LIMIT")

		let retryNode = BinaryNode(
			tag: "receipt",
			attrs: [
				"from": "123@s.whatsapp.net",
				"id": "3EB0LIMIT",
				"type": "retry",
				"participant": "123:2@s.whatsapp.net"
			],
			content: .nodes([BinaryNode(tag: "retry", attrs: ["count": "2"])])
		)
		await client.handleIncomingNode(retryNode)
		await client.handleIncomingNode(retryNode)

		let nodes = try await sentReceiptNodes(from: transport, count: 4)
		#expect(nodes.count == 4)
		#expect(nodes.map(\.tag) == ["message", "ack", "message", "ack"])
		#expect(nodes[2].attrs["to"] == "123:2@s.whatsapp.net")
		#expect(nodes.filter { $0.tag == "message" && $0.attrs["to"] == "123:2@s.whatsapp.net" }.count == 1)
	}
}

private func firstReceiptAck(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	let frame = try #require(await transport.sentFrames.first)
	var codec = NoiseFrameCodec()
	return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
}

private func sentReceiptNodes(from transport: MockMessageSendWebSocketTransport, count: Int) async throws -> [BinaryNode] {
	for _ in 0..<100 where await transport.sentFrames.count < count {
		try await Task.sleep(for: .milliseconds(1))
	}

	let frames = await Array(transport.sentFrames.prefix(count))
	return try frames.map { frame in
		var codec = NoiseFrameCodec()
		return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
	}
}
