public struct ReceivedCommentContent: Equatable, Sendable {
	public let content: ReceivedMessageContent?
	public let targetMessageKey: ReceivedMessageKey?

	public init(content: ReceivedMessageContent?, targetMessageKey: ReceivedMessageKey?) {
		self.content = content
		self.targetMessageKey = targetMessageKey
	}
}
