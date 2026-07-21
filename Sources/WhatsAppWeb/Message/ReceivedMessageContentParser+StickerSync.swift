extension ReceivedMessageContentParser {
	static func stickerSyncRMRContent(
		_ stickerSync: Proto_Message.StickerSyncRMRMessage
	) -> ReceivedStickerSyncRMRContent {
		ReceivedStickerSyncRMRContent(
			filehash: stickerSync.filehash,
			rmrSource: stickerSync.hasRmrSource ? stickerSync.rmrSource : nil,
			requestTimestamp: stickerSync.hasRequestTimestamp ? stickerSync.requestTimestamp : nil
		)
	}
}
