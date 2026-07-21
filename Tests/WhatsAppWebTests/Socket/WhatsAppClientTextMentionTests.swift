import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client text mentions")
struct WhatsAppClientTextMentionTests {
	@Test("encodes mentioned JIDs in text message context info")
	func encodesMentionedJIDsInTextMessageContextInfo() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x10]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendTextMessage(
			to: "123@s.whatsapp.net",
			content: OutgoingTextContent(
				text: "@alice hello",
				mentions: ["111@s.whatsapp.net"],
				mentionAll: true,
				isForwarded: true,
				forwardingScore: 3
			),
			messageID: "3EB0MENTION"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.extendedTextMessage.text == "@alice hello")
		#expect(message.extendedTextMessage.contextInfo.mentionedJid == ["111@s.whatsapp.net"])
		#expect(message.extendedTextMessage.contextInfo.nonJidMentions == 1)
		#expect(message.extendedTextMessage.contextInfo.isForwarded == true)
		#expect(message.extendedTextMessage.contextInfo.forwardingScore == 3)
	}

	@Test("encodes quoted text message in context info")
	func encodesQuotedTextMessageInContextInfo() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x11]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendTextMessage(
			to: "123@s.whatsapp.net",
			text: "reply from swift",
			quoted: OutgoingQuotedTextContent(
				chatJID: "123@s.whatsapp.net",
				messageID: "3EB0QUOTED",
				participantJID: "456@s.whatsapp.net",
				text: "original text"
			),
			messageID: "3EB0REPLY"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		let contextInfo = message.extendedTextMessage.contextInfo
		#expect(contextInfo.stanzaID == "3EB0QUOTED")
		#expect(contextInfo.participant == "456@s.whatsapp.net")
		#expect(contextInfo.hasRemoteJid == false)
		#expect(contextInfo.quotedMessage.extendedTextMessage.text == "original text")
	}

	@Test("encodes disappearing text expiration in context info")
	func encodesDisappearingTextExpirationInContextInfo() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x12]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendTextMessage(
			to: "123@s.whatsapp.net",
			text: "expires",
			ephemeralExpiration: 86_400,
			messageID: "3EB0EPHEMERALTEXT"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.extendedTextMessage.text == "expires")
		#expect(message.extendedTextMessage.contextInfo.expiration == 86_400)
	}
}
