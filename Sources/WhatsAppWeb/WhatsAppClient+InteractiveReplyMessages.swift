extension WhatsAppClient {
	public func sendButtonReplyMessage(
		to destinationJID: String,
		content: OutgoingButtonReplyContent,
		messageID: String? = nil
	) async throws -> String {
		return try await sendResolvedMessage(
			to: destinationJID,
			message: MessageContentBuilder.buttonReply(content),
			messageID: messageID
		)
	}

	public func sendListReplyMessage(
		to destinationJID: String,
		content: OutgoingListReplyContent,
		messageID: String? = nil
	) async throws -> String {
		return try await sendResolvedMessage(
			to: destinationJID,
			message: MessageContentBuilder.listReply(content),
			messageID: messageID
		)
	}
}
