extension ReceivedMessageContentParser {
	static func commentContent(_ comment: Proto_Message.CommentMessage) -> ReceivedCommentContent {
		ReceivedCommentContent(
			content: comment.hasMessage ? parse(comment.message) : nil,
			targetMessageKey: comment.hasTargetMessageKey ? messageKey(comment.targetMessageKey) : nil
		)
	}
}
