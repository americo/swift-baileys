import Foundation

extension WhatsAppClient {
	public func sendProductMessage(
		to destinationJID: String,
		imageData: Data,
		product: OutgoingProductContent,
		messageID: String? = nil
	) async throws -> String {
		guard let mediaUploader else {
			throw WhatsAppClientError.missingMediaUploader
		}

		let mediaKey = try mediaKeyGenerator.makeMediaKey()
		let encryptedMedia = try MediaEncryption.encrypt(imageData, mediaKey: mediaKey, mediaType: .image)
		let upload = try await mediaUploader.upload(
			encryptedMedia.encryptedFile,
			fileEncSha256Base64: encryptedMedia.fileEncSha256.base64EncodedString(),
			mediaType: .image
		)
		let image = UploadedImageContent(
			url: upload.mediaURL,
			directPath: upload.directPath,
			mediaKey: mediaKey,
			fileEncSha256: encryptedMedia.fileEncSha256,
			fileSha256: encryptedMedia.fileSha256,
			fileLength: UInt64(encryptedMedia.fileLength),
			mediaKeyTimestamp: mediaKeyTimestamp(),
			mimetype: "image/jpeg",
			caption: nil,
			jpegThumbnail: product.jpegThumbnail
		)

		return try await sendResolvedMessage(
			to: destinationJID,
			message: MessageContentBuilder.product(UploadedProductContent(
				image: image,
				product: product
			)),
			messageID: messageID
		)
	}
}
