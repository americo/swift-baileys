public struct ReceivedStickerSyncRMRContent: Equatable, Sendable {
	public let filehash: [String]
	public let rmrSource: String?
	public let requestTimestamp: Int64?

	public init(filehash: [String], rmrSource: String?, requestTimestamp: Int64?) {
		self.filehash = filehash
		self.rmrSource = rmrSource
		self.requestTimestamp = requestTimestamp
	}
}
