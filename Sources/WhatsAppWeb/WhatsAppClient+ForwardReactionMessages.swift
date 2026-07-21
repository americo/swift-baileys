enum ForwardReactionMessageMapper {
	static func message(from content: ReceivedReactionContent) -> Proto_Message {
		var reaction = Proto_Message.ReactionMessage()
		if let key = content.key {
			reaction.key = ForwardMessageKeyMapper.key(from: key)
		}
		if let text = content.text {
			reaction.text = text
		}
		if let groupingKey = content.groupingKey {
			reaction.groupingKey = groupingKey
		}
		if let senderTimestampMilliseconds = content.senderTimestampMilliseconds {
			reaction.senderTimestampMs = senderTimestampMilliseconds
		}

		var message = Proto_Message()
		message.reactionMessage = reaction
		return message
	}
}
