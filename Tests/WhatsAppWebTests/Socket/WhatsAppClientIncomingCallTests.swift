import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client incoming calls")
struct WhatsAppClientIncomingCallTests {
	@Test("emits offer call events with media and group metadata")
	func emitsOfferCallEventsWithMediaAndGroupMetadata() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "call",
			attrs: ["from": "123@g.us", "id": "call-node-1", "t": "1700000000", "offline": "1"],
			content: .nodes([
				BinaryNode(
					tag: "offer",
					attrs: [
						"call-id": "call-1",
						"from": "456@s.whatsapp.net",
						"type": "group",
						"group-jid": "123@g.us",
						"caller_pn": "456@s.whatsapp.net"
					],
					content: .nodes([BinaryNode(tag: "video")])
				)
			])
		))

		#expect(await events.next() == .call([
			WhatsAppCallEvent(
				chatID: "123@g.us",
				from: "456@s.whatsapp.net",
				callerPN: "456@s.whatsapp.net",
				isGroup: true,
				groupJID: "123@g.us",
				id: "call-1",
				date: Date(timeIntervalSince1970: 1_700_000_000),
				isVideo: true,
				status: .offer,
				offline: true
			)
		]))
	}

	@Test("enriches terminal call events from cached offer metadata")
	func enrichesTerminalCallEventsFromCachedOfferMetadata() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "call",
			attrs: ["from": "123@g.us", "id": "call-node-1", "t": "1700000000"],
			content: .nodes([
				BinaryNode(
					tag: "offer",
					attrs: ["call-id": "call-1", "from": "456@s.whatsapp.net", "type": "group"],
					content: .nodes([BinaryNode(tag: "video")])
				)
			])
		))
		_ = await events.next()

		await client.handleIncomingNode(BinaryNode(
			tag: "call",
			attrs: ["from": "123@g.us", "id": "call-node-2", "t": "1700000005"],
			content: .nodes([
				BinaryNode(tag: "terminate", attrs: ["call-id": "call-1", "call-creator": "456@s.whatsapp.net"])
			])
		))

		#expect(await events.next() == .call([
			WhatsAppCallEvent(
				chatID: "123@g.us",
				from: "456@s.whatsapp.net",
				isGroup: true,
				id: "call-1",
				date: Date(timeIntervalSince1970: 1_700_000_005),
				isVideo: true,
				status: .terminate,
				offline: false
			)
		]))
	}

	@Test("acknowledges processed call stanzas")
	func acknowledgesProcessedCallStanzas() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "call",
			attrs: ["from": "123@s.whatsapp.net", "id": "call-node-ack", "t": "1700000000"],
			content: .nodes([
				BinaryNode(tag: "offer", attrs: ["call-id": "call-1", "from": "123@s.whatsapp.net"])
			])
		))

		let ack = try await firstCallAck(from: transport)
		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: ["id": "call-node-ack", "to": "123@s.whatsapp.net", "class": "call"]
		))
	}

	@Test("acknowledges and drops calls filtered by configuration")
	func acknowledgesAndDropsCallsFilteredByConfiguration() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(
			configuration: WhatsAppClientConfiguration(shouldIgnoreJID: { $0 == "123@s.whatsapp.net" }),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "call",
			attrs: ["from": "123@s.whatsapp.net", "id": "ignored-call-1"],
			content: .nodes([
				BinaryNode(tag: "offer", attrs: ["call-id": "call-1", "from": "123@s.whatsapp.net"])
			])
		))

		let ack = try await firstCallAck(from: transport)
		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: ["id": "ignored-call-1", "to": "123@s.whatsapp.net", "class": "call"]
		))
	}
}

private func firstCallAck(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	let frame = try #require(await transport.sentFrames.first)
	var codec = NoiseFrameCodec()
	return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
}
