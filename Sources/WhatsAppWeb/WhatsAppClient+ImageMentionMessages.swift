import Foundation

extension WhatsAppClient {
	public func sendImageMessage(
		to destinationJID: String,
		imageData: Data,
		caption: String? = nil,
		mentions: [String],
		mentionAll: Bool = false,
		ephemeralExpiration: UInt32? = nil,
		viewOnce: Bool = false,
		albumParentKey: WhatsAppMessageKey? = nil,
		messageID: String? = nil
	) async throws -> String {
		let uploaded = try await uploadMedia(imageData, mediaType: .image)
		var message = MessageContentBuilder.imageWithMentions(
			MessageContentBuilder.uploadedImage(UploadedImageContent(
				url: uploaded.result.mediaURL,
				directPath: uploaded.result.directPath,
				mediaKey: uploaded.mediaKey,
				fileEncSha256: uploaded.encryptedMedia.fileEncSha256,
				fileSha256: uploaded.encryptedMedia.fileSha256,
				fileLength: UInt64(uploaded.encryptedMedia.fileLength),
				mediaKeyTimestamp: mediaKeyTimestamp(),
				mimetype: "image/jpeg",
				caption: caption
			)),
			mentions: mentions,
			mentionAll: mentionAll,
			ephemeralExpiration: ephemeralExpiration
		)
		message = wrapViewOnce(message, enabled: viewOnce)
		if let albumParentKey {
			message = MessageContentBuilder.withAlbumParent(message, parent: albumParentKey)
		}

		return try await sendResolvedMessage(
			to: destinationJID,
			message: message,
			messageID: messageID
		)
	}
}
