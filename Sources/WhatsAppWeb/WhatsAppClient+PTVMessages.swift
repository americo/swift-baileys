import Foundation

extension WhatsAppClient {
	public func sendPTVMessage(
		to destinationJID: String,
		videoData: Data,
		video: OutgoingVideoContent,
		viewOnce: Bool = false,
		messageID: String? = nil
	) async throws -> String {
		let uploaded = try await uploadMedia(videoData, mediaType: .video)
		return try await sendResolvedMessage(
			to: destinationJID,
			message: wrapViewOnce(MessageContentBuilder.uploadedPTV(UploadedVideoContent(
				url: uploaded.result.mediaURL,
				directPath: uploaded.result.directPath,
				mediaKey: uploaded.mediaKey,
				fileEncSha256: uploaded.encryptedMedia.fileEncSha256,
				fileSha256: uploaded.encryptedMedia.fileSha256,
				fileLength: UInt64(uploaded.encryptedMedia.fileLength),
				mediaKeyTimestamp: mediaKeyTimestamp(),
				video: video
			)), enabled: viewOnce),
			messageID: messageID
		)
	}
}
