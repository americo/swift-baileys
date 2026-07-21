enum ForwardCommentMessageMapper {
	static func message(
		from source: Proto_Message.CommentMessage,
		fromMe: Bool,
		forceForward: Bool
	) throws -> Proto_Message {
		var comment = source
		if source.hasMessage {
			comment.message = try MessageContentBuilder.forward(
				source.message,
				fromMe: fromMe,
				forceForward: forceForward
			)
		}
		var message = Proto_Message()
		message.commentMessage = comment
		return message
	}

	static func message(from content: ReceivedCommentContent) throws -> Proto_Message {
		var comment = Proto_Message.CommentMessage()
		if let nestedContent = content.content {
			comment.message = try ForwardNestedMessageMapper.message(from: nestedContent)
		}
		if let targetMessageKey = content.targetMessageKey {
			comment.targetMessageKey = ForwardMessageKeyMapper.key(from: targetMessageKey)
		}
		var message = Proto_Message()
		message.commentMessage = comment
		return message
	}
}
