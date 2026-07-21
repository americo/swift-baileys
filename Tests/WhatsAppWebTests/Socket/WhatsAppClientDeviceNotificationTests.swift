import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client device notifications")
struct WhatsAppClientDeviceNotificationTests {
	@Test("emits device list updates grouped by user")
	func emitsDeviceListUpdatesGroupedByUser() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "devices-1", "type": "devices"],
			content: .nodes([
				BinaryNode(tag: "add", attrs: ["device_hash": "hash-1"], content: .nodes([
					BinaryNode(tag: "device", attrs: ["jid": "123:1@s.whatsapp.net"]),
					BinaryNode(tag: "device", attrs: ["jid": "123:2@s.whatsapp.net"]),
					BinaryNode(tag: "device", attrs: ["jid": "456:1@s.whatsapp.net"])
				]))
			])
		))

		#expect(await events.next() == .deviceListUpdated([
			DeviceListUpdate(
				user: "123",
				action: .add,
				deviceHash: "hash-1",
				devices: [
					WhatsAppDevice(jid: "123:1@s.whatsapp.net", user: "123", server: "s.whatsapp.net", device: 1),
					WhatsAppDevice(jid: "123:2@s.whatsapp.net", user: "123", server: "s.whatsapp.net", device: 2)
				]
			),
			DeviceListUpdate(
				user: "456",
				action: .add,
				deviceHash: "hash-1",
				devices: [
					WhatsAppDevice(jid: "456:1@s.whatsapp.net", user: "456", server: "s.whatsapp.net", device: 1)
				]
			)
		]))
	}

	@Test("emits remove device notifications and acknowledges them")
	func emitsRemoveDeviceNotificationsAndAcknowledgesThem() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "devices-2", "type": "devices"],
			content: .nodes([
				BinaryNode(tag: "remove", attrs: ["device_hash": "hash-2"], content: .nodes([
					BinaryNode(tag: "device", attrs: ["jid": "123:3@s.whatsapp.net"]),
					BinaryNode(tag: "device", attrs: ["jid": "not-a-jid"])
				]))
			])
		))

		#expect(await events.next() == .deviceListUpdated([
			DeviceListUpdate(
				user: "123",
				action: .remove,
				deviceHash: "hash-2",
				devices: [
					WhatsAppDevice(jid: "123:3@s.whatsapp.net", user: "123", server: "s.whatsapp.net", device: 3)
				]
			)
		]))
		let ack = try await firstDeviceNotificationAck(from: transport)
		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: ["id": "devices-2", "to": "@s.whatsapp.net", "class": "notification", "type": "devices"]
		))
	}
}

private func firstDeviceNotificationAck(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	let frame = try #require(await transport.sentFrames.first)
	var codec = NoiseFrameCodec()
	return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
}
