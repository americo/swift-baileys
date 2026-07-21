extension ReceivedMessageContentParser {
	static func messageHistoryBundleContent(
		_ bundle: Proto_Message.MessageHistoryBundle
	) -> ReceivedMessageHistoryBundleContent {
		ReceivedMessageHistoryBundleContent(
			mimetype: bundle.hasMimetype ? bundle.mimetype : nil,
			fileSHA256: bundle.hasFileSha256 ? bundle.fileSha256 : nil,
			mediaKey: bundle.hasMediaKey ? bundle.mediaKey : nil,
			fileEncSHA256: bundle.hasFileEncSha256 ? bundle.fileEncSha256 : nil,
			directPath: bundle.hasDirectPath ? bundle.directPath : nil,
			mediaKeyTimestamp: bundle.hasMediaKeyTimestamp ? bundle.mediaKeyTimestamp : nil,
			metadata: bundle.hasMessageHistoryMetadata
				? messageHistoryMetadataContent(bundle.messageHistoryMetadata)
				: nil
		)
	}

	static func messageHistoryNoticeContent(
		_ notice: Proto_Message.MessageHistoryNotice
	) -> ReceivedMessageHistoryNoticeContent {
		ReceivedMessageHistoryNoticeContent(
			metadata: notice.hasMessageHistoryMetadata ? messageHistoryMetadataContent(notice.messageHistoryMetadata) : nil
		)
	}

	static func messageHistoryMetadataContent(
		_ metadata: Proto_Message.MessageHistoryMetadata
	) -> ReceivedMessageHistoryMetadataContent {
		ReceivedMessageHistoryMetadataContent(
			historyReceivers: metadata.historyReceivers,
			oldestMessageTimestamp: metadata.hasOldestMessageTimestamp ? metadata.oldestMessageTimestamp : nil,
			messageCount: metadata.hasMessageCount ? metadata.messageCount : nil
		)
	}
}
