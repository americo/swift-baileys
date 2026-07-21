import Foundation

public enum ReceivedHistorySyncType: Equatable, Sendable {
	case initialBootstrap
	case initialStatusV3
	case full
	case recent
	case pushName
	case nonBlockingData
	case onDemand
	case noHistory
	case messageAccessStatus
	case unrecognized(Int)
}

public struct ReceivedHistorySyncMessageAccessStatusContent: Equatable, Sendable {
	public let completeAccessGranted: Bool?

	public init(completeAccessGranted: Bool?) {
		self.completeAccessGranted = completeAccessGranted
	}
}

public struct ReceivedHistorySyncNotificationContent: Equatable, Sendable {
	public let fileSHA256: Data?
	public let fileLength: UInt64?
	public let mediaKey: Data?
	public let fileEncSHA256: Data?
	public let directPath: String?
	public let syncType: ReceivedHistorySyncType?
	public let chunkOrder: UInt32?
	public let originalMessageID: String?
	public let progress: UInt32?
	public let oldestMessageInChunkTimestampSeconds: Int64?
	public let initialHistoryBootstrapInlinePayload: Data?
	public let peerDataRequestSessionID: String?
	public let encryptedHandle: String?
	public let messageAccessStatus: ReceivedHistorySyncMessageAccessStatusContent?

	public init(
		fileSHA256: Data?,
		fileLength: UInt64?,
		mediaKey: Data?,
		fileEncSHA256: Data?,
		directPath: String?,
		syncType: ReceivedHistorySyncType?,
		chunkOrder: UInt32?,
		originalMessageID: String?,
		progress: UInt32?,
		oldestMessageInChunkTimestampSeconds: Int64?,
		initialHistoryBootstrapInlinePayload: Data?,
		peerDataRequestSessionID: String?,
		encryptedHandle: String?,
		messageAccessStatus: ReceivedHistorySyncMessageAccessStatusContent?
	) {
		self.fileSHA256 = fileSHA256
		self.fileLength = fileLength
		self.mediaKey = mediaKey
		self.fileEncSHA256 = fileEncSHA256
		self.directPath = directPath
		self.syncType = syncType
		self.chunkOrder = chunkOrder
		self.originalMessageID = originalMessageID
		self.progress = progress
		self.oldestMessageInChunkTimestampSeconds = oldestMessageInChunkTimestampSeconds
		self.initialHistoryBootstrapInlinePayload = initialHistoryBootstrapInlinePayload
		self.peerDataRequestSessionID = peerDataRequestSessionID
		self.encryptedHandle = encryptedHandle
		self.messageAccessStatus = messageAccessStatus
	}
}
