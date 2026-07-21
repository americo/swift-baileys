import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client incoming notifications")
struct WhatsAppClientIncomingNotificationTests {
	@Test("emits app state sync request from server sync notifications")
	func emitsAppStateSyncRequestFromServerSyncNotifications() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "server-sync-1", "type": "server_sync"],
			content: .nodes([
				BinaryNode(tag: "collection", attrs: ["name": "critical_block"])
			])
		))

		#expect(await events.next() == .appStateSyncRequested(AppStateSyncRequest(collections: ["critical_block"])))
	}

	@Test("acknowledges processed server sync notifications")
	func acknowledgesProcessedServerSyncNotifications() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "server-sync-ack", "type": "server_sync"],
			content: .nodes([
				BinaryNode(tag: "collection", attrs: ["name": "regular_high"])
			])
		))

		let ack = try await firstNotificationAck(from: transport)
		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: ["id": "server-sync-ack", "to": "@s.whatsapp.net", "class": "notification", "type": "server_sync"]
		))
	}

	@Test("automatically requests app state sync from server sync notifications")
	func automaticallyRequestsAppStateSyncFromServerSyncNotifications() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: appStateCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "server-sync-auto", "type": "server_sync"],
			content: .nodes([
				BinaryNode(tag: "collection", attrs: ["name": "regular_low"]),
				BinaryNode(tag: "collection", attrs: ["name": "unknown"])
			])
		))

		let ack = try await transport.waitForSentNode(at: 0)
		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: ["id": "server-sync-auto", "to": "@s.whatsapp.net", "class": "notification", "type": "server_sync"]
		))
		let request = try await transport.waitForSentNode(at: 1)
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "w:sync:app:state")
		let collection = try #require(request.firstChild(named: "sync")?.firstChild(named: "collection"))
		#expect(collection.attrs["name"] == "regular_low")
		#expect(collection.attrs["version"] == "0")
		#expect(collection.attrs["return_snapshot"] == "true")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": try #require(request.attrs["id"]), "type": "result"],
			content: .nodes([
				BinaryNode(tag: "sync", content: .nodes([
					BinaryNode(tag: "collection", attrs: [
						"name": "regular_low",
						"version": "0",
						"has_more_patches": "false"
					])
				]))
			])
		))
	}

	@Test("emits contact updates from picture set notifications")
	func emitsContactUpdatesFromPictureSetNotifications() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "123:45@s.whatsapp.net", "id": "picture-1", "type": "picture"],
			content: .nodes([
				BinaryNode(tag: "set", attrs: ["id": "profile-hash-1"])
			])
		))

		#expect(await events.next() == .contactsUpdated([
			ContactUpdate(id: "123@s.whatsapp.net", imageURL: "changed")
		]))
	}

	@Test("emits contact updates from picture delete notifications and acknowledges them")
	func emitsContactUpdatesFromPictureDeleteNotificationsAndAcknowledgesThem() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "123@s.whatsapp.net", "id": "picture-2", "type": "picture"],
			content: .nodes([
				BinaryNode(tag: "delete")
			])
		))

		#expect(await events.next() == .contactsUpdated([
			ContactUpdate(id: "123@s.whatsapp.net", imageURL: "removed")
		]))
		let ack = try await firstNotificationAck(from: transport)
		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: ["id": "picture-2", "to": "123@s.whatsapp.net", "class": "notification", "type": "picture"]
		))
	}

	@Test("acknowledges and drops notifications filtered by configuration")
	func acknowledgesAndDropsNotificationsFilteredByConfiguration() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(
			configuration: WhatsAppClientConfiguration(shouldIgnoreJID: { $0 == "123@s.whatsapp.net" }),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "123@s.whatsapp.net", "id": "ignored-notification-1", "type": "picture"],
			content: .nodes([BinaryNode(tag: "set", attrs: ["id": "profile-hash-1"])])
		))

		let ack = try await firstNotificationAck(from: transport)
		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: [
				"id": "ignored-notification-1",
				"to": "123@s.whatsapp.net",
				"class": "notification",
				"type": "picture"
			]
		))
	}

	@Test("emits group icon stub messages from group picture notifications")
	func emitsGroupIconStubMessagesFromGroupPictureNotifications() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: [
				"from": "123@g.us",
				"id": "group-picture-1",
				"t": "1700000800",
				"type": "picture"
			],
			content: .nodes([
				BinaryNode(tag: "set", attrs: [
					"id": "profile-hash-1",
					"author": "456@s.whatsapp.net"
				])
			])
		))

		#expect(await events.next() == .contactsUpdated([
			ContactUpdate(id: "123@g.us", imageURL: "changed")
		]))
		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "group-picture-1",
			from: "123@g.us",
			timestamp: 1_700_000_800,
			content: .stub(ReceivedMessageStubContent(
				type: .groupChangeIcon,
				parameters: ["profile-hash-1"]
			)),
			fromMe: false,
			participant: "456@s.whatsapp.net",
			keyParticipant: "456@s.whatsapp.net",
			stub: ReceivedMessageStubContent(type: .groupChangeIcon, parameters: ["profile-hash-1"])
		)))
	}

	@Test("emits media updates from media retry notifications")
	func emitsMediaUpdatesFromMediaRetryNotifications() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "123@s.whatsapp.net", "id": "media-retry-1", "type": "mediaretry"],
			content: .nodes([
				BinaryNode(
					tag: "rmr",
					attrs: [
						"jid": "123@s.whatsapp.net",
						"from_me": "true",
						"participant": "456@s.whatsapp.net"
					]
				),
				BinaryNode(tag: "encrypt", content: .nodes([
					BinaryNode(tag: "enc_p", content: .data(Data([0x01, 0x02]))),
					BinaryNode(tag: "enc_iv", content: .data(Data([0x03, 0x04])))
				]))
			])
		))

		#expect(await events.next() == .messageMediaUpdated([
			MessageMediaUpdate(
				key: WhatsAppMessageKey(
					remoteJID: "123@s.whatsapp.net",
					fromMe: true,
					id: "media-retry-1",
					participant: "456@s.whatsapp.net"
				),
				media: RetriedMedia(ciphertext: Data([0x01, 0x02]), iv: Data([0x03, 0x04]))
			)
		]))
	}

	@Test("emits media retry errors and acknowledges them")
	func emitsMediaRetryErrorsAndAcknowledgesThem() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "123@s.whatsapp.net", "id": "media-retry-2", "type": "mediaretry"],
			content: .nodes([
				BinaryNode(tag: "rmr", attrs: ["jid": "123@s.whatsapp.net", "from_me": "false"]),
				BinaryNode(tag: "error", attrs: ["code": "2"])
			])
		))

		#expect(await events.next() == .messageMediaUpdated([
			MessageMediaUpdate(
				key: WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "media-retry-2"),
				errorCode: 2,
				errorStatusCode: 404
			)
		]))
		let ack = try await firstNotificationAck(from: transport)
		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: ["id": "media-retry-2", "to": "123@s.whatsapp.net", "class": "notification", "type": "mediaretry"]
		))
	}
}

private func firstNotificationAck(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	let frame = try #require(await transport.sentFrames.first)
	var codec = NoiseFrameCodec()
	return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
}
