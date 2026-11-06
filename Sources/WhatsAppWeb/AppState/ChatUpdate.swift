public struct ChatUpdate: Equatable, Sendable {
	public let id: String
	public let muteEndTime: Int64?
	public let archived: Bool?
	public let unreadCount: Int?
	public let pinned: Int64?
	/// Whether the chat is muted now. `muteEndTime` alone cannot tell "unmuted" from "not part of this update".
	public let isMuted: Bool?
	/// Whether the chat is pinned now. `pinned` alone cannot tell "unpinned" from "not part of this update".
	public let isPinned: Bool?

	public init(
		id: String,
		muteEndTime: Int64? = nil,
		archived: Bool? = nil,
		unreadCount: Int? = nil,
		pinned: Int64? = nil,
		isMuted: Bool? = nil,
		isPinned: Bool? = nil
	) {
		self.id = id
		self.muteEndTime = muteEndTime
		self.archived = archived
		self.unreadCount = unreadCount
		self.pinned = pinned
		self.isMuted = isMuted
		self.isPinned = isPinned
	}
}
