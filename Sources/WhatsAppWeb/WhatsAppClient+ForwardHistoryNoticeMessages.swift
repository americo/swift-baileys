enum ForwardHistoryNoticeMessageMapper {
	static func message(from content: ReceivedMessageHistoryNoticeContent) -> Proto_Message {
		var notice = Proto_Message.MessageHistoryNotice()
		if let metadata = content.metadata {
			var protoMetadata = Proto_Message.MessageHistoryMetadata()
			protoMetadata.historyReceivers = metadata.historyReceivers
			if let oldestMessageTimestamp = metadata.oldestMessageTimestamp {
				protoMetadata.oldestMessageTimestamp = oldestMessageTimestamp
			}
			if let messageCount = metadata.messageCount {
				protoMetadata.messageCount = messageCount
			}
			notice.messageHistoryMetadata = protoMetadata
		}

		var message = Proto_Message()
		message.messageHistoryNotice = notice
		return message
	}
}
