extension WhatsAppClient {
	public func sendLimitSharingMessage(
		to destinationJID: String,
		content: OutgoingLimitSharingContent,
		messageID: String? = nil
	) async throws -> String {
		return try await sendResolvedMessage(
			to: destinationJID,
			message: MessageContentBuilder.limitSharing(content),
			messageID: messageID
		)
	}
}
