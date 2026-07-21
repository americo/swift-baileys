public struct ReceivedQuestionResponseContent: Equatable, Sendable {
	public let key: ReceivedMessageKey?
	public let text: String?

	public init(key: ReceivedMessageKey?, text: String?) {
		self.key = key
		self.text = text
	}
}
