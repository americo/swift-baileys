import Testing
@testable import WhatsAppWeb

@Suite("Message forward comment content builder")
struct MessageForwardCommentContentBuilderTests {
	@Test("forwards comment messages by preserving target key and forwarding nested content")
	func forwardsCommentMessagesByPreservingTargetKeyAndForwardingNestedContent() throws {
		var target = Proto_MessageKey()
		target.remoteJid = "status@broadcast"
		target.id = "target-status"
		var comment = Proto_Message.CommentMessage()
		comment.targetMessageKey = target
		comment.message = MessageContentBuilder.text("comment text")
		var source = Proto_Message()
		source.commentMessage = comment

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.targetMessageKey.remoteJid == "status@broadcast")
		#expect(message.commentMessage.targetMessageKey.id == "target-status")
		#expect(message.commentMessage.message.hasExtendedTextMessage)
		#expect(message.commentMessage.message.extendedTextMessage.text == "comment text")
		#expect(message.commentMessage.message.extendedTextMessage.contextInfo.isForwarded)
		#expect(message.commentMessage.message.extendedTextMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards empty comment messages as pass-through content")
	func forwardsEmptyCommentMessagesAsPassThroughContent() throws {
		var source = Proto_Message()
		source.commentMessage = Proto_Message.CommentMessage()

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.hasMessage == false)
		#expect(message.commentMessage.hasTargetMessageKey == false)
	}
}
