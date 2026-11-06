import Foundation

/// A sticker the user saved as favourite (or used recently) on their phone, synced as an app state
/// `StickerAction`. It holds what is needed to download and decrypt the `.webp` file.
public struct FavoriteSticker: Equatable, Sendable, Identifiable {
	/// Base64 of the file hash, taken from the mutation index. Stable across syncs.
	public let id: String
	public let url: String
	public let directPath: String
	public let mediaKey: Data
	public let fileEncSHA256: Data
	public let mimetype: String
	public let width: UInt32
	public let height: UInt32
	public let fileLength: UInt64
	public let isFavorite: Bool
	public let isLottie: Bool
	public let isAvatarSticker: Bool
	/// Seconds since 1970 of the action, used to order the most recent first.
	public let timestamp: Int64

	public init(
		id: String,
		url: String,
		directPath: String,
		mediaKey: Data,
		fileEncSHA256: Data,
		mimetype: String,
		width: UInt32,
		height: UInt32,
		fileLength: UInt64,
		isFavorite: Bool,
		isLottie: Bool,
		isAvatarSticker: Bool,
		timestamp: Int64
	) {
		self.id = id
		self.url = url
		self.directPath = directPath
		self.mediaKey = mediaKey
		self.fileEncSHA256 = fileEncSHA256
		self.mimetype = mimetype
		self.width = width
		self.height = height
		self.fileLength = fileLength
		self.isFavorite = isFavorite
		self.isLottie = isLottie
		self.isAvatarSticker = isAvatarSticker
		self.timestamp = timestamp
	}
}

public struct FavoriteStickerUpdate: Equatable, Sendable {
	public let sticker: FavoriteSticker
	/// True when the phone removed the sticker from its list.
	public let removed: Bool

	public init(sticker: FavoriteSticker, removed: Bool) {
		self.sticker = sticker
		self.removed = removed
	}
}
