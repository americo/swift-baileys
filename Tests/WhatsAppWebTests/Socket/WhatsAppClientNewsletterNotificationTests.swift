import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client newsletter notifications")
struct WhatsAppClientNewsletterNotificationTests {
	@Test("emits reaction and view newsletter updates")
	func emitsReactionAndViewNewsletterUpdates() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: [
				"from": "120363000000000010@newsletter",
				"id": "newsletter-1",
				"participant": "123@s.whatsapp.net",
				"type": "newsletter"
			],
			content: .nodes([
				BinaryNode(
					tag: "reaction",
					attrs: ["message_id": "server-message-1"],
					content: .nodes([BinaryNode(tag: "reaction", content: .string("🔥"))])
				),
				BinaryNode(tag: "view", attrs: ["message_id": "server-message-2"], content: .string("42"))
			])
		))

		#expect(await events.next() == .newsletterReactionUpdated(NewsletterReactionUpdate(
			id: "120363000000000010@newsletter",
			serverID: "server-message-1",
			code: "🔥",
			count: 1
		)))
		#expect(await events.next() == .newsletterViewUpdated(NewsletterViewUpdate(
			id: "120363000000000010@newsletter",
			serverID: "server-message-2",
			count: 42
		)))
	}

	@Test("emits participant and settings newsletter updates and acknowledges them")
	func emitsParticipantAndSettingsNewsletterUpdatesAndAcknowledgesThem() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: [
				"from": "120363000000000010@newsletter",
				"id": "newsletter-2",
				"participant": "123@s.whatsapp.net",
				"type": "newsletter"
			],
			content: .nodes([
				BinaryNode(tag: "participant", attrs: [
					"jid": "456@s.whatsapp.net",
					"action": "promote",
					"role": "ADMIN"
				]),
				BinaryNode(tag: "update", content: .nodes([
					BinaryNode(tag: "settings", content: .nodes([
						BinaryNode(tag: "name", content: .string("Swift News")),
						BinaryNode(tag: "description", content: .data(Data("Daily Swift updates".utf8)))
					]))
				]))
			])
		))

		#expect(await events.next() == .newsletterParticipantsUpdated(NewsletterParticipantUpdate(
			id: "120363000000000010@newsletter",
			author: "123@s.whatsapp.net",
			user: "456@s.whatsapp.net",
			action: "promote",
			newRole: "ADMIN"
		)))
		#expect(await events.next() == .newsletterSettingsUpdated(NewsletterSettingsUpdate(
			id: "120363000000000010@newsletter",
			name: "Swift News",
			description: "Daily Swift updates"
		)))
		let ack = try await firstNewsletterNotificationAck(from: transport)
		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: [
				"id": "newsletter-2",
				"to": "120363000000000010@newsletter",
				"class": "notification",
				"participant": "123@s.whatsapp.net",
				"type": "newsletter"
			]
		))
	}

	@Test("emits plaintext newsletter messages as received messages")
	func emitsPlaintextNewsletterMessagesAsReceivedMessages() async throws {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()
		var message = Proto_Message()
		message.conversation = "newsletter hello"

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: [
				"from": "120363000000000010@newsletter",
				"id": "newsletter-3",
				"participant": "123@s.whatsapp.net",
				"type": "newsletter"
			],
			content: .nodes([
				BinaryNode(tag: "message", attrs: [
					"message_id": "server-message-3",
					"t": "1710000000"
				], content: .nodes([
					BinaryNode(tag: "plaintext", content: .data(try message.serializedData()))
				]))
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "server-message-3",
			from: "120363000000000010@newsletter",
			timestamp: 1_710_000_000,
			content: .text("newsletter hello"),
			fromMe: false
		)))
	}
}

private func firstNewsletterNotificationAck(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	let frame = try #require(await transport.sentFrames.first)
	var codec = NoiseFrameCodec()
	return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
}
