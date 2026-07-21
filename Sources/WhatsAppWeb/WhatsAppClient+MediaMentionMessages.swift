import Foundation

extension WhatsAppClient {
	public func sendDocumentMessage(
		to destinationJID: String,
		documentData: Data,
		document: OutgoingDocumentContent,
		mentions: [String],
		mentionAll: Bool = false,
		ephemeralExpiration: UInt32? = nil,
		viewOnce: Bool = false,
		messageID: String? = nil
	) async throws -> String {
		let uploaded = try await uploadMedia(documentData, mediaType: .document)
		let message = MessageContentBuilder.documentWithMentions(
			MessageContentBuilder.uploadedDocument(UploadedDocumentContent(
				url: uploaded.result.mediaURL,
				directPath: uploaded.result.directPath,
				mediaKey: uploaded.mediaKey,
				fileEncSha256: uploaded.encryptedMedia.fileEncSha256,
				fileSha256: uploaded.encryptedMedia.fileSha256,
				fileLength: UInt64(uploaded.encryptedMedia.fileLength),
				mediaKeyTimestamp: mediaKeyTimestamp(),
				document: document
			)),
			mentions: mentions,
			mentionAll: mentionAll,
			ephemeralExpiration: ephemeralExpiration
		)

		return try await sendResolvedMessage(
			to: destinationJID,
			message: wrapViewOnce(message, enabled: viewOnce),
			messageID: messageID
		)
	}

	public func sendVideoMessage(
		to destinationJID: String,
		videoData: Data,
		video: OutgoingVideoContent,
		mentions: [String],
		mentionAll: Bool = false,
		ephemeralExpiration: UInt32? = nil,
		viewOnce: Bool = false,
		albumParentKey: WhatsAppMessageKey? = nil,
		messageID: String? = nil
	) async throws -> String {
		let uploaded = try await uploadMedia(videoData, mediaType: .video)
		var message = MessageContentBuilder.videoWithMentions(
			MessageContentBuilder.uploadedVideo(UploadedVideoContent(
				url: uploaded.result.mediaURL,
				directPath: uploaded.result.directPath,
				mediaKey: uploaded.mediaKey,
				fileEncSha256: uploaded.encryptedMedia.fileEncSha256,
				fileSha256: uploaded.encryptedMedia.fileSha256,
				fileLength: UInt64(uploaded.encryptedMedia.fileLength),
				mediaKeyTimestamp: mediaKeyTimestamp(),
				video: video
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
