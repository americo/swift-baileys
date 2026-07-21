import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message encrypted payload parser")
struct ReceivedMessageEncryptedPayloadParserTests {
	@Test("parses encrypted comment messages")
	func parsesEncryptedCommentMessages() throws {
		var target = Proto_MessageKey()
		target.remoteJid = "status@broadcast"
		target.id = "comment-target"
		var comment = Proto_Message.EncCommentMessage()
		comment.targetMessageKey = target
		comment.encPayload = Data([1, 2, 3])
		comment.encIv = Data([4, 5, 6])
		var message = Proto_Message()
		message.encCommentMessage = comment

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .encryptedComment(ReceivedEncryptedCommentContent(
			targetMessageKey: ReceivedMessageKey(remoteJID: "status@broadcast", fromMe: false, id: "comment-target", participant: nil),
			encryptedPayload: Data([1, 2, 3]),
			encryptedIV: Data([4, 5, 6])
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses encrypted reaction messages")
	func parsesEncryptedReactionMessages() throws {
		var target = Proto_MessageKey()
		target.remoteJid = "123@s.whatsapp.net"
		target.id = "reaction-target"
		target.participant = "456@s.whatsapp.net"
		var reaction = Proto_Message.EncReactionMessage()
		reaction.targetMessageKey = target
		reaction.encPayload = Data([0x11, 0x12])
		reaction.encIv = Data([0x13, 0x14])
		var message = Proto_Message()
		message.encReactionMessage = reaction

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .encryptedReaction(ReceivedEncryptedReactionContent(
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: false,
				id: "reaction-target",
				participant: "456@s.whatsapp.net"
			),
			encryptedPayload: Data([0x11, 0x12]),
			encryptedIV: Data([0x13, 0x14])
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses secret encrypted messages")
	func parsesSecretEncryptedMessages() throws {
		var target = Proto_MessageKey()
		target.remoteJid = "123@s.whatsapp.net"
		target.id = "secret-target"
		var secret = Proto_Message.SecretEncryptedMessage()
		secret.targetMessageKey = target
		secret.encPayload = Data([7, 8])
		secret.encIv = Data([9, 10])
		secret.secretEncType = .messageEdit
		var message = Proto_Message()
		message.secretEncryptedMessage = secret

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .secretEncrypted(ReceivedSecretEncryptedContent(
			targetMessageKey: ReceivedMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "secret-target", participant: nil),
			encryptedPayload: Data([7, 8]),
			encryptedIV: Data([9, 10]),
			type: .messageEdit
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent optional encrypted payload fields")
	func preservesAbsentOptionalEncryptedPayloadFields() throws {
		var message = Proto_Message()
		message.secretEncryptedMessage = Proto_Message.SecretEncryptedMessage()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .secretEncrypted(ReceivedSecretEncryptedContent(
			targetMessageKey: nil,
			encryptedPayload: nil,
			encryptedIV: nil,
			type: nil
		)))
	}
}
