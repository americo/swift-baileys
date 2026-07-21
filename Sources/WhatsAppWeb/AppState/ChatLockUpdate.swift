public struct ChatLockUpdate: Equatable, Sendable {
	public let id: String
	public let locked: Bool

	public init(id: String, locked: Bool) {
		self.id = id
		self.locked = locked
	}
}
