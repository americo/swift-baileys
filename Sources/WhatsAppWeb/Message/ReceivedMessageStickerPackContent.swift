import Foundation

public enum ReceivedStickerPackOrigin: Equatable, Sendable {
	case firstParty
	case thirdParty
	case userCreated
	case unrecognized(Int)
}

public struct ReceivedStickerPackStickerContent: Equatable, Sendable {
	public let fileName: String?
	public let isAnimated: Bool?
	public let emojis: [String]
	public let accessibilityLabel: String?
	public let isLottie: Bool?
	public let mimetype: String?

	public init(
		fileName: String?,
		isAnimated: Bool?,
		emojis: [String],
		accessibilityLabel: String?,
		isLottie: Bool?,
		mimetype: String?
	) {
		self.fileName = fileName
		self.isAnimated = isAnimated
		self.emojis = emojis
		self.accessibilityLabel = accessibilityLabel
		self.isLottie = isLottie
		self.mimetype = mimetype
	}
}

public struct ReceivedStickerPackContent: Equatable, Sendable {
	public let id: String?
	public let name: String?
	public let publisher: String?
	public let stickers: [ReceivedStickerPackStickerContent]
	public let fileLength: UInt64?
	public let fileSHA256: Data?
	public let fileEncSHA256: Data?
	public let mediaKey: Data?
	public let directPath: String?
	public let caption: String?
	public let packDescription: String?
	public let mediaKeyTimestamp: Int64?
	public let trayIconFileName: String?
	public let thumbnailDirectPath: String?
	public let thumbnailSHA256: Data?
	public let thumbnailEncSHA256: Data?
	public let thumbnailHeight: UInt32?
	public let thumbnailWidth: UInt32?
	public let imageDataHash: String?
	public let stickerPackSize: UInt64?
	public let origin: ReceivedStickerPackOrigin?

	public init(
		id: String?,
		name: String?,
		publisher: String?,
		stickers: [ReceivedStickerPackStickerContent],
		fileLength: UInt64?,
		fileSHA256: Data?,
		fileEncSHA256: Data?,
		mediaKey: Data?,
		directPath: String?,
		caption: String?,
		packDescription: String?,
		mediaKeyTimestamp: Int64?,
		trayIconFileName: String?,
		thumbnailDirectPath: String?,
		thumbnailSHA256: Data?,
		thumbnailEncSHA256: Data?,
		thumbnailHeight: UInt32?,
		thumbnailWidth: UInt32?,
		imageDataHash: String?,
		stickerPackSize: UInt64?,
		origin: ReceivedStickerPackOrigin?
	) {
		self.id = id
		self.name = name
		self.publisher = publisher
		self.stickers = stickers
		self.fileLength = fileLength
		self.fileSHA256 = fileSHA256
		self.fileEncSHA256 = fileEncSHA256
		self.mediaKey = mediaKey
		self.directPath = directPath
		self.caption = caption
		self.packDescription = packDescription
		self.mediaKeyTimestamp = mediaKeyTimestamp
		self.trayIconFileName = trayIconFileName
		self.thumbnailDirectPath = thumbnailDirectPath
		self.thumbnailSHA256 = thumbnailSHA256
		self.thumbnailEncSHA256 = thumbnailEncSHA256
		self.thumbnailHeight = thumbnailHeight
		self.thumbnailWidth = thumbnailWidth
		self.imageDataHash = imageDataHash
		self.stickerPackSize = stickerPackSize
		self.origin = origin
	}
}
