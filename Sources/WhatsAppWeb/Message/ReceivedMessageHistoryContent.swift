import Foundation

public struct ReceivedMessageHistoryMetadataContent: Equatable, Sendable {
	public let historyReceivers: [String]
	public let oldestMessageTimestamp: Int64?
	public let messageCount: Int64?

	public init(historyReceivers: [String], oldestMessageTimestamp: Int64?, messageCount: Int64?) {
		self.historyReceivers = historyReceivers
		self.oldestMessageTimestamp = oldestMessageTimestamp
		self.messageCount = messageCount
	}
}

public struct ReceivedMessageHistoryNoticeContent: Equatable, Sendable {
	public let metadata: ReceivedMessageHistoryMetadataContent?

	public init(metadata: ReceivedMessageHistoryMetadataContent?) {
		self.metadata = metadata
	}
}

public struct ReceivedMessageHistoryBundleContent: Equatable, Sendable {
	public let mimetype: String?
	public let fileSHA256: Data?
	public let mediaKey: Data?
	public let fileEncSHA256: Data?
	public let directPath: String?
	public let mediaKeyTimestamp: Int64?
	public let metadata: ReceivedMessageHistoryMetadataContent?

	public init(
		mimetype: String?,
		fileSHA256: Data?,
		mediaKey: Data?,
		fileEncSHA256: Data?,
		directPath: String?,
		mediaKeyTimestamp: Int64?,
		metadata: ReceivedMessageHistoryMetadataContent?
	) {
		self.mimetype = mimetype
		self.fileSHA256 = fileSHA256
		self.mediaKey = mediaKey
		self.fileEncSHA256 = fileEncSHA256
		self.directPath = directPath
		self.mediaKeyTimestamp = mediaKeyTimestamp
		self.metadata = metadata
	}
}
