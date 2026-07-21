public struct ReceivedPeerDataOperationRequestResponseContent: Equatable, Sendable {
	public let stanzaID: String?
	public let placeholderResendMessages: [ReceivedMessage]

	public init(
		stanzaID: String?,
		placeholderResendMessages: [ReceivedMessage]
	) {
		self.stanzaID = stanzaID
		self.placeholderResendMessages = placeholderResendMessages
	}
}
