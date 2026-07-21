extension WhatsAppClient {
	public func sendDisappearingMessagesSetting(
		to destinationJID: String,
		content: OutgoingDisappearingMessagesContent,
		messageID: String? = nil
	) async throws -> String {
		return try await sendResolvedMessage(
			to: destinationJID,
			message: MessageContentBuilder.disappearingMessages(content),
			messageID: messageID
		)
	}
}
