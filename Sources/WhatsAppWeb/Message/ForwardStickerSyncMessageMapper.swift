enum ForwardStickerSyncMessageMapper {
	static func stickerSyncRMR(from content: ReceivedStickerSyncRMRContent) -> Proto_Message {
		var stickerSync = Proto_Message.StickerSyncRMRMessage()
		stickerSync.filehash = content.filehash
		if let rmrSource = content.rmrSource {
			stickerSync.rmrSource = rmrSource
		}
		if let requestTimestamp = content.requestTimestamp {
			stickerSync.requestTimestamp = requestTimestamp
		}
		var message = Proto_Message()
		message.stickerSyncRmrMessage = stickerSync
		return message
	}
}
