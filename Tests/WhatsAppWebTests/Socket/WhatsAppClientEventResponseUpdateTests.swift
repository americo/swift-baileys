import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client event response updates")
struct WhatsAppClientEventResponseUpdateTests {
	@Test("incoming encrypted event response messages emit updates before the envelope")
	func incomingEncryptedEventResponseMessagesEmitUpdatesBeforeTheEnvelope() async throws {
		var key = Proto_MessageKey()
		key.remoteJid = "120363000000000000@g.us"
		key.fromMe = false
		key.id = "EVENT_TARGET"
		key.participant = "258840000000@s.whatsapp.net"
		var response = Proto_Message.EncEventResponseMessage()
		response.eventCreationMessageKey = key
		response.encPayload = Data([0x01, 0x02, 0x03, 0x04])
		response.encIv = Data([0x05, 0x06, 0x07])
		var message = Proto_Message()
		message.encEventResponseMessage = response
		let client = WhatsAppClient(messageDecryptor: EventResponseUpdateDecryptor(message: message))
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(eventResponseUpdateNode(id: "event-response-message"))

		#expect(await events.next() == .messageEventResponsesUpdated([
			ReceivedMessageEventResponseUpdate(
				key: WhatsAppMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "EVENT_TARGET",
					participant: "258840000000@s.whatsapp.net"
				),
				eventResponseMessageKey: WhatsAppMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "event-response-message",
					participant: "456@s.whatsapp.net"
				),
				encryptedPayload: Data([0x01, 0x02, 0x03, 0x04]),
				encryptedIV: Data([0x05, 0x06, 0x07])
			)
		]))
		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "event-response-message",
			from: "120363000000000000@g.us",
			timestamp: 1_700_000_007,
			content: .encryptedEventResponse(ReceivedEncryptedEventResponseContent(
				eventCreationMessageKey: ReceivedMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "EVENT_TARGET",
					participant: "258840000000@s.whatsapp.net"
				),
				encryptedPayload: Data([0x01, 0x02, 0x03, 0x04]),
				encryptedIV: Data([0x05, 0x06, 0x07])
			)),
			participant: "456@s.whatsapp.net"
		)))
	}

	@Test("incoming event response updates include decrypted responses when context is available")
	func incomingEventResponseUpdatesIncludeDecryptedResponsesWhenContextIsAvailable() async throws {
		let secret = try Data(hexString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
		let encrypted = try EventResponseCipher(ivGenerator: {
			try Data(hexString: "202122232425262728292a2b")
		}).encrypt(
			OutgoingEventResponseContent(
				response: .going,
				timestampMilliseconds: 1_800_000_123_456,
				extraGuestCount: 2
			),
			eventMessageID: "EVENT_TARGET",
			eventCreatorJID: "258840000000@s.whatsapp.net",
			responderJID: "456@s.whatsapp.net",
			eventMessageSecret: secret
		)
		var key = Proto_MessageKey()
		key.remoteJid = "120363000000000000@g.us"
		key.fromMe = false
		key.id = "EVENT_TARGET"
		key.participant = "258840000000@s.whatsapp.net"
		var response = Proto_Message.EncEventResponseMessage()
		response.eventCreationMessageKey = key
		response.encPayload = encrypted.encPayload
		response.encIv = encrypted.encIv
		var message = Proto_Message()
		message.encEventResponseMessage = response
		let client = WhatsAppClient(messageDecryptor: EventResponseUpdateDecryptor(message: message))
		await client.configureEventResponseContextResolver(EventResponseContextResolver(context: EventResponseDecryptionContext(
			eventMessageID: "EVENT_TARGET",
			eventCreatorJID: "258840000000@s.whatsapp.net",
			responderJID: "456@s.whatsapp.net",
			eventMessageSecret: secret
		)))
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(eventResponseUpdateNode(id: "event-response-message"))

		#expect(await events.next() == .messageEventResponsesUpdated([
			ReceivedMessageEventResponseUpdate(
				key: WhatsAppMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "EVENT_TARGET",
					participant: "258840000000@s.whatsapp.net"
				),
				eventResponseMessageKey: WhatsAppMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "event-response-message",
					participant: "456@s.whatsapp.net"
				),
				encryptedPayload: encrypted.encPayload,
				encryptedIV: encrypted.encIv,
				response: ReceivedEventResponseContent(
					response: .going,
					timestampMilliseconds: 1_800_000_123_456,
					extraGuestCount: 2
				)
			)
		]))
	}
}

private struct EventResponseUpdateDecryptor: IncomingMessageDecrypting {
	let message: Proto_Message

	func decryptIncomingMessage(from node: BinaryNode) async throws -> Proto_Message? {
		message
	}
}

private struct EventResponseContextResolver: EventResponseContextResolving {
	let context: EventResponseDecryptionContext

	func context(
		for key: WhatsAppMessageKey,
		responseMessageKey: WhatsAppMessageKey
	) async throws -> EventResponseDecryptionContext? {
		context
	}
}

private func eventResponseUpdateNode(id: String) -> BinaryNode {
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

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw EventResponseUpdateTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}
}

private enum EventResponseUpdateTestError: Error {
	case invalidHex
}
