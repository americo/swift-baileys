import Foundation

extension WhatsAppClient {
	/// Downloads and decrypts a favourite sticker. The sync action carries no plaintext hash, so only
	/// the encrypted file hash and the MAC are verified.
	public func downloadFavoriteSticker(_ sticker: FavoriteSticker) async throws -> Data {
		var url = URL(string: sticker.url)
		if !sticker.directPath.isEmpty {
			let host = url?.host ?? MediaDirectPathURLResolver.defaultHost
			url = MediaDirectPathURLResolver.url(from: sticker.directPath, host: host) ?? url
		}
		guard let url, url.scheme != nil else {
			throw ReceivedMessageContentParserError.invalidMediaURL
		}
		return try await mediaDownloader.download(
			url: url,
			mediaKey: sticker.mediaKey,
			mediaType: .sticker,
			fileEncSHA256: sticker.fileEncSHA256
		)
	}

	/// Sends a favourite sticker by downloading it and uploading it again, which keeps the send path
	/// identical to any other sticker.
	@discardableResult
	public func sendFavoriteSticker(_ sticker: FavoriteSticker, to destinationJID: String) async throws -> String {
		let data = try await downloadFavoriteSticker(sticker)
		return try await sendStickerMessage(
			to: destinationJID,
			stickerData: data,
			sticker: OutgoingStickerContent(
				mimetype: sticker.mimetype.isEmpty ? "image/webp" : sticker.mimetype,
				width: sticker.width == 0 ? nil : sticker.width,
				height: sticker.height == 0 ? nil : sticker.height
			)
		)
	}
}
