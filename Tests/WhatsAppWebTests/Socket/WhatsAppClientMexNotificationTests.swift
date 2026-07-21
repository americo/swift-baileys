import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client MEX notifications")
struct WhatsAppClientMexNotificationTests {
	@Test("emits reachout timelock updates from MEX notifications")
	func emitsReachoutTimelockUpdatesFromMexNotifications() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "mex-1", "type": "mex"],
			content: .nodes([
				BinaryNode(
					tag: "update",
					attrs: ["op_name": "NotificationUserReachoutTimelockUpdate"],
					content: .data(Data("""
					{"data":{"xwa2_notify_account_reachout_timelock":{"is_active":true,"enforcement_type":"WEB_COMPANION_ONLY","time_enforcement_ends":"1710000600"}}}
					""".utf8))
				)
			])
		))

		#expect(await events.next() == .reachoutTimelockUpdated(ReachoutTimelockUpdate(
			isActive: true,
			timeEnforcementEnds: Date(timeIntervalSince1970: 1_710_000_600),
			enforcementType: "WEB_COMPANION_ONLY"
		)))
		let ack = try await firstMexNotificationAck(from: transport)
		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: ["id": "mex-1", "to": "@s.whatsapp.net", "class": "notification", "type": "mex"]
		))
	}

	@Test("emits message capping updates from MEX notifications")
	func emitsMessageCappingUpdatesFromMexNotifications() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "mex-2", "type": "mex"],
			content: .nodes([
				BinaryNode(
					tag: "update",
					attrs: ["op_name": "MessageCappingInfoNotification"],
					content: .string("""
					{"data":{"xwa2_notify_new_chat_messages_capping_info_update":{"total_quota":100,"used_quota":40,"cycle_start_timestamp":"1710000000","cycle_end_timestamp":"1710086400","server_sent_timestamp":"1710000300","ote_status":"ELIGIBLE","mv_status":"ACTIVE","capping_status":"FIRST_WARNING"}}}
					""")
				)
			])
		))

		#expect(await events.next() == .messageCappingUpdated(MessageCappingUpdate(
			totalQuota: 100,
			usedQuota: 40,
			cycleStartTimestamp: "1710000000",
			cycleEndTimestamp: "1710086400",
			serverSentTimestamp: "1710000300",
			oteStatus: "ELIGIBLE",
			mvStatus: "ACTIVE",
			cappingStatus: "FIRST_WARNING"
		)))
	}
}

private func firstMexNotificationAck(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	let frame = try #require(await transport.sentFrames.first)
	var codec = NoiseFrameCodec()
	return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
}
