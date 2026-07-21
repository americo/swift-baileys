public struct ChatUpdate: Equatable, Sendable {
	public let id: String
	public let muteEndTime: Int64?
	public let archived: Bool?
	public let unreadCount: Int?
	public let pinned: Int64?

	public init(
		id: String,
		muteEndTime: Int64? = nil,
		archived: Bool? = nil,
		unreadCount: Int? = nil,
		pinned: Int64? = nil
	) {
		self.id = id
		self.muteEndTime = muteEndTime
		self.archived = archived
		self.unreadCount = unreadCount
		self.pinned = pinned
	}
}
