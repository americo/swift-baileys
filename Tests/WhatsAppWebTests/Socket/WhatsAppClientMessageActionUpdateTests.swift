import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client message action updates")
struct WhatsAppClientMessageActionUpdateTests {
	@Test("incoming pin messages emit target message updates before the envelope")
	func incomingPinMessagesEmitTargetMessageUpdatesBeforeTheEnvelope() async throws {
		var pin = Proto_Message.PinInChatMessage()
		pin.key = messageActionTargetKey(id: "PIN_TARGET")
		pin.type = .pinForAll
		pin.senderTimestampMs = 1_700_333_444_000
		var message = Proto_Message()
		message.pinInChatMessage = pin
		let client = WhatsAppClient(messageDecryptor: MessageActionUpdateDecryptor(message: message))
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(messageActionUpdateNode(id: "pin-envelope"))

		let content = ReceivedMessageContent.messagePin(ReceivedMessagePinContent(
			key: targetReceivedKey(id: "PIN_TARGET"),
			action: .pinForAll,
			senderTimestampMilliseconds: 1_700_333_444_000
		))
		#expect(await events.next() == .messagesUpdated([
			ReceivedMessageUpdate(
				key: targetWhatsAppKey(id: "PIN_TARGET"),
				status: nil,
				timestamp: 1_700_333_444,
				content: content
			)
		]))
		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "pin-envelope",
			from: "120363000000000000@g.us",
			timestamp: 1_700_000_007,
			content: content,
			participant: "456@s.whatsapp.net"
		)))
	}

	@Test("incoming keep messages emit target message updates before the envelope")
	func incomingKeepMessagesEmitTargetMessageUpdatesBeforeTheEnvelope() async throws {
		var keep = Proto_Message.KeepInChatMessage()
		keep.key = messageActionTargetKey(id: "KEEP_TARGET")
		keep.keepType = .keepForAll
		keep.timestampMs = 1_700_444_555_000
		var message = Proto_Message()
		message.keepInChatMessage = keep
		let client = WhatsAppClient(messageDecryptor: MessageActionUpdateDecryptor(message: message))
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(messageActionUpdateNode(id: "keep-envelope"))

		let content = ReceivedMessageContent.messageKeep(ReceivedMessageKeepContent(
			key: targetReceivedKey(id: "KEEP_TARGET"),
			action: .keepForAll,
			timestampMilliseconds: 1_700_444_555_000
		))
		#expect(await events.next() == .messagesUpdated([
			ReceivedMessageUpdate(
				key: targetWhatsAppKey(id: "KEEP_TARGET"),
				status: nil,
				timestamp: 1_700_444_555,
				content: content
			)
		]))
		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "keep-envelope",
			from: "120363000000000000@g.us",
			timestamp: 1_700_000_007,
			content: content,
			participant: "456@s.whatsapp.net"
		)))
	}
}

private struct MessageActionUpdateDecryptor: IncomingMessageDecrypting {
	let message: Proto_Message

	func decryptIncomingMessage(from node: BinaryNode) async throws -> Proto_Message? {
		message
	}
}

private func messageActionTargetKey(id: String) -> Proto_MessageKey {
	var key = Proto_MessageKey()
	key.remoteJid = "120363000000000000@g.us"
	key.fromMe = false
	key.id = id
	key.participant = "258840000000@s.whatsapp.net"
	return key
}

private func targetReceivedKey(id: String) -> ReceivedMessageKey {
	ReceivedMessageKey(
		remoteJID: "120363000000000000@g.us",
		fromMe: false,
		id: id,
		participant: "258840000000@s.whatsapp.net"
	)
}

private func targetWhatsAppKey(id: String) -> WhatsAppMessageKey {
	WhatsAppMessageKey(
		remoteJID: "120363000000000000@g.us",
		fromMe: false,
		id: id,
		participant: "258840000000@s.whatsapp.net"
	)
}

private func messageActionUpdateNode(id: String) -> BinaryNode {
	BinaryNode(
		tag: "message",
		attrs: [
			"id": id,
			"from": "120363000000000000@g.us",
			"participant": "456@s.whatsapp.net",
			"t": "1700000007"
		],
		content: .nodes([
			BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0xaa, 0xbb])))
		])
	)
}
