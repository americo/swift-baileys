import Testing
@testable import WhatsAppWeb

@Suite("Received message comment parser")
struct ReceivedMessageCommentParserTests {
	@Test("parses comment messages")
	func parsesCommentMessages() throws {
		var target = Proto_MessageKey()
		target.remoteJid = "status@broadcast"
		target.id = "target-status"
		var comment = Proto_Message.CommentMessage()
		comment.targetMessageKey = target
		comment.message = MessageContentBuilder.text("comment text")
		var message = Proto_Message()
		message.commentMessage = comment

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .comment(ReceivedCommentContent(
			content: .text("comment text"),
			targetMessageKey: ReceivedMessageKey(remoteJID: "status@broadcast", fromMe: false, id: "target-status", participant: nil)
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent optional comment fields")
	func preservesAbsentOptionalCommentFields() throws {
		var message = Proto_Message()
		message.commentMessage = Proto_Message.CommentMessage()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .comment(ReceivedCommentContent(
			content: nil,
			targetMessageKey: nil
		)))
	}
}
