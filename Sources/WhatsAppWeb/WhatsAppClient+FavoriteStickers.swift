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
}
