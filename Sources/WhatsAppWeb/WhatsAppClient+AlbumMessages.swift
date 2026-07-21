extension WhatsAppClient {
	public func sendAlbumMessage(
		to destinationJID: String,
		album: OutgoingAlbumContent,
		messageID: String? = nil
	) async throws -> String {
		return try await sendResolvedMessage(
			to: destinationJID,
			message: MessageContentBuilder.album(album),
			messageID: messageID
		)
	}
}
