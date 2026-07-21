enum ForwardStickerPackMessageMapper {
	static func message(from content: ReceivedStickerPackContent) -> Proto_Message {
		var pack = Proto_Message.StickerPackMessage()
		if let id = content.id {
			pack.stickerPackID = id
		}
		if let name = content.name {
			pack.name = name
		}
		if let publisher = content.publisher {
			pack.publisher = publisher
		}
		pack.stickers = content.stickers.map(sticker)
		if let fileLength = content.fileLength {
			pack.fileLength = fileLength
		}
		if let fileSHA256 = content.fileSHA256 {
			pack.fileSha256 = fileSHA256
		}
		if let fileEncSHA256 = content.fileEncSHA256 {
			pack.fileEncSha256 = fileEncSHA256
		}
		if let mediaKey = content.mediaKey {
			pack.mediaKey = mediaKey
		}
		if let directPath = content.directPath {
			pack.directPath = directPath
		}
		if let caption = content.caption {
			pack.caption = caption
		}
		if let packDescription = content.packDescription {
			pack.packDescription = packDescription
		}
		if let mediaKeyTimestamp = content.mediaKeyTimestamp {
			pack.mediaKeyTimestamp = mediaKeyTimestamp
		}
		if let trayIconFileName = content.trayIconFileName {
			pack.trayIconFileName = trayIconFileName
		}
		if let thumbnailDirectPath = content.thumbnailDirectPath {
			pack.thumbnailDirectPath = thumbnailDirectPath
		}
		if let thumbnailSHA256 = content.thumbnailSHA256 {
			pack.thumbnailSha256 = thumbnailSHA256
		}
		if let thumbnailEncSHA256 = content.thumbnailEncSHA256 {
			pack.thumbnailEncSha256 = thumbnailEncSHA256
		}
		if let thumbnailHeight = content.thumbnailHeight {
			pack.thumbnailHeight = thumbnailHeight
		}
		if let thumbnailWidth = content.thumbnailWidth {
			pack.thumbnailWidth = thumbnailWidth
		}
		if let imageDataHash = content.imageDataHash {
			pack.imageDataHash = imageDataHash
		}
		if let stickerPackSize = content.stickerPackSize {
			pack.stickerPackSize = stickerPackSize
		}
		if let origin = content.origin {
			pack.stickerPackOrigin = stickerPackOrigin(from: origin)
		}

		var message = Proto_Message()
		message.stickerPackMessage = pack
		return message
	}

	private static func sticker(
		from content: ReceivedStickerPackStickerContent
	) -> Proto_Message.StickerPackMessage.Sticker {
		var sticker = Proto_Message.StickerPackMessage.Sticker()
		if let fileName = content.fileName {
			sticker.fileName = fileName
		}
		if let isAnimated = content.isAnimated {
			sticker.isAnimated = isAnimated
		}
		sticker.emojis = content.emojis
		if let accessibilityLabel = content.accessibilityLabel {
			sticker.accessibilityLabel = accessibilityLabel
		}
		if let isLottie = content.isLottie {
			sticker.isLottie = isLottie
		}
		if let mimetype = content.mimetype {
			sticker.mimetype = mimetype
		}
		return sticker
	}

	private static func stickerPackOrigin(
		from origin: ReceivedStickerPackOrigin
	) -> Proto_Message.StickerPackMessage.StickerPackOrigin {
		switch origin {
		case .firstParty:
			.firstParty
		case .thirdParty:
			.thirdParty
		case .userCreated:
			.userCreated
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}
}
