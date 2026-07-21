import Foundation

enum ForwardHistoryBundleMessageMapper {
	static func message(from content: ReceivedMessageHistoryBundleContent) -> Proto_Message {
		var bundle = Proto_Message.MessageHistoryBundle()
		if let mimetype = content.mimetype {
			bundle.mimetype = mimetype
		}
		if let fileSHA256 = content.fileSHA256 {
			bundle.fileSha256 = fileSHA256
		}
		if let mediaKey = content.mediaKey {
			bundle.mediaKey = mediaKey
		}
		if let fileEncSHA256 = content.fileEncSHA256 {
			bundle.fileEncSha256 = fileEncSHA256
		}
		if let directPath = content.directPath {
			bundle.directPath = directPath
		}
		if let mediaKeyTimestamp = content.mediaKeyTimestamp {
			bundle.mediaKeyTimestamp = mediaKeyTimestamp
		}
		if let metadata = content.metadata {
			var protoMetadata = Proto_Message.MessageHistoryMetadata()
			protoMetadata.historyReceivers = metadata.historyReceivers
			if let oldestMessageTimestamp = metadata.oldestMessageTimestamp {
				protoMetadata.oldestMessageTimestamp = oldestMessageTimestamp
			}
			if let messageCount = metadata.messageCount {
				protoMetadata.messageCount = messageCount
			}
			bundle.messageHistoryMetadata = protoMetadata
		}

		var message = Proto_Message()
		message.messageHistoryBundle = bundle
		return message
	}
}
