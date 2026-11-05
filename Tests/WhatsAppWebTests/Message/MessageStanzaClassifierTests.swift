import Foundation
import Testing
@testable import WhatsAppWeb

private struct FixedMessageEncryptor: MessageEncrypting {
	func encryptMessage(jid: String, data: Data) async throws -> EncryptedMessage {
		EncryptedMessage(type: "msg", ciphertext: Data([0x01]))
	}
}

@Suite("Message stanza classifier")
struct MessageStanzaClassifierTests {
	private func stanza(for message: Proto_Message) async throws -> BinaryNode {
		let builder = MessageRelayBuilder(
			encoder: MessageEncoder(randomByte: { 0x00 }),
			encryptor: FixedMessageEncryptor()
		)
		return try await builder.buildDirectMessageStanza(
			to: "123@s.whatsapp.net",
			messageID: "ID",
			message: message,
			recipientDeviceJIDs: ["123@s.whatsapp.net"]
		)
	}

	private func encAttribute(of stanza: BinaryNode) -> String? {
		stanza.firstChild(named: "participants")?.firstChild(named: "to")?.firstChild(named: "enc")?.attrs["mediatype"]
	}

	@Test("text stays a text stanza without a media type")
	func textStanza() async throws {
		let result = try await stanza(for: MessageContentBuilder.text("hello"))
		#expect(result.attrs["type"] == "text")
		#expect(encAttribute(of: result) == nil)
	}

	@Test("a reaction travels as a reaction stanza that hides decryption failures")
	func reactionStanza() async throws {
		let message = MessageContentBuilder.reaction(
			"❤️",
			to: MessageReactionTarget(chatJID: "123@s.whatsapp.net", messageID: "TARGET", fromMe: false),
			timestampMilliseconds: 1
		)
		let result = try await stanza(for: message)
		let enc = result.firstChild(named: "participants")?.firstChild(named: "to")?.firstChild(named: "enc")
		#expect(result.attrs["type"] == "reaction")
		#expect(enc?.attrs["decrypt-fail"] == "hide")
		#expect(enc?.attrs["mediatype"] == nil)
	}

	@Test("deleting for everyone stays a text stanza that hides decryption failures")
	func revokeStanza() async throws {
		let message = MessageContentBuilder.delete(target: WhatsAppMessageKey(
			remoteJID: "123@s.whatsapp.net", fromMe: true, id: "TARGET", participant: nil
		))
		let result = try await stanza(for: message)
		let enc = result.firstChild(named: "participants")?.firstChild(named: "to")?.firstChild(named: "enc")
		#expect(result.attrs["type"] == "text")
		#expect(enc?.attrs["decrypt-fail"] == "hide")
	}

	@Test("media travels as a media stanza naming its type", arguments: [
		("image", { var m = Proto_Message(); m.imageMessage = .init(); return m }() as Proto_Message),
		("document", { var m = Proto_Message(); m.documentMessage = .init(); return m }() as Proto_Message),
		("video", { var m = Proto_Message(); m.videoMessage = .init(); return m }() as Proto_Message),
		("gif", { var m = Proto_Message(); m.videoMessage.gifPlayback = true; return m }() as Proto_Message),
		("audio", { var m = Proto_Message(); m.audioMessage = .init(); return m }() as Proto_Message),
		("ptt", { var m = Proto_Message(); m.audioMessage.ptt = true; return m }() as Proto_Message)
	])
	func mediaStanza(expected: String, message: Proto_Message) async throws {
		let result = try await stanza(for: message)
		#expect(result.attrs["type"] == "media")
		#expect(encAttribute(of: result) == expected)
	}

	@Test("context adds the reply and mentions to a media message")
	func contextOnImage() {
		var image = Proto_Message()
		image.imageMessage.caption = "hi"
		let message = MessageContentBuilder.withContext(
			image,
			mentions: ["1@s.whatsapp.net"],
			quoted: OutgoingQuotedTextContent(chatJID: "c@g.us", messageID: "Q", participantJID: "p@s.whatsapp.net", text: "t"),
			quotedRemoteJID: nil
		)
		#expect(message.imageMessage.caption == "hi")
		#expect(message.imageMessage.contextInfo.mentionedJid == ["1@s.whatsapp.net"])
		#expect(message.imageMessage.contextInfo.stanzaID == "Q")
		#expect(message.imageMessage.contextInfo.participant == "p@s.whatsapp.net")
	}
}
