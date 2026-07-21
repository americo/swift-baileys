import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Message forward encrypted payload content builder")
struct MessageForwardEncryptedPayloadContentBuilderTests {
	@Test("forwards encrypted comment and secret encrypted messages as pass-through content")
	func forwardsEncryptedCommentAndSecretEncryptedMessagesAsPassThroughContent() throws {
		var target = Proto_MessageKey()
		target.remoteJid = "status@broadcast"
		target.id = "target-status"

		var comment = Proto_Message.EncCommentMessage()
		comment.targetMessageKey = target
		comment.encPayload = Data([0x01, 0x02])
		comment.encIv = Data([0x03, 0x04])
		var commentSource = Proto_Message()
		commentSource.encCommentMessage = comment

		let commentMessage = try MessageContentBuilder.forward(commentSource, fromMe: false)

		#expect(commentMessage.hasEncCommentMessage)
		#expect(commentMessage.encCommentMessage.targetMessageKey.id == "target-status")
		#expect(commentMessage.encCommentMessage.encPayload == Data([0x01, 0x02]))
		#expect(commentMessage.encCommentMessage.encIv == Data([0x03, 0x04]))

		var reaction = Proto_Message.EncReactionMessage()
		reaction.targetMessageKey = target
		reaction.encPayload = Data([0x09, 0x0a])
		reaction.encIv = Data([0x0b, 0x0c])
		var reactionSource = Proto_Message()
		reactionSource.encReactionMessage = reaction

		let reactionMessage = try MessageContentBuilder.forward(reactionSource, fromMe: false)

		#expect(reactionMessage.hasEncReactionMessage)
		#expect(reactionMessage.encReactionMessage.targetMessageKey.remoteJid == "status@broadcast")
		#expect(reactionMessage.encReactionMessage.encPayload == Data([0x09, 0x0a]))
		#expect(reactionMessage.encReactionMessage.encIv == Data([0x0b, 0x0c]))

		var secret = Proto_Message.SecretEncryptedMessage()
		secret.targetMessageKey = target
		secret.encPayload = Data([0x05, 0x06])
		secret.encIv = Data([0x07, 0x08])
		secret.secretEncType = .messageEdit
		var secretSource = Proto_Message()
		secretSource.secretEncryptedMessage = secret

		let secretMessage = try MessageContentBuilder.forward(secretSource, fromMe: false)

		#expect(secretMessage.hasSecretEncryptedMessage)
		#expect(secretMessage.secretEncryptedMessage.targetMessageKey.remoteJid == "status@broadcast")
		#expect(secretMessage.secretEncryptedMessage.encPayload == Data([0x05, 0x06]))
		#expect(secretMessage.secretEncryptedMessage.encIv == Data([0x07, 0x08]))
		#expect(secretMessage.secretEncryptedMessage.secretEncType == .messageEdit)
	}
}
