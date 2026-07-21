extension ReceivedMessageContentParser {
	static func stickerPackContent(_ pack: Proto_Message.StickerPackMessage) -> ReceivedStickerPackContent {
		ReceivedStickerPackContent(
			id: pack.hasStickerPackID ? pack.stickerPackID : nil,
			name: pack.hasName ? pack.name : nil,
			publisher: pack.hasPublisher ? pack.publisher : nil,
			stickers: pack.stickers.map(stickerContent),
			fileLength: pack.hasFileLength ? pack.fileLength : nil,
			fileSHA256: pack.hasFileSha256 ? pack.fileSha256 : nil,
			fileEncSHA256: pack.hasFileEncSha256 ? pack.fileEncSha256 : nil,
			mediaKey: pack.hasMediaKey ? pack.mediaKey : nil,
			directPath: pack.hasDirectPath ? pack.directPath : nil,
			caption: pack.hasCaption ? pack.caption : nil,
			packDescription: pack.hasPackDescription ? pack.packDescription : nil,
			mediaKeyTimestamp: pack.hasMediaKeyTimestamp ? pack.mediaKeyTimestamp : nil,
			trayIconFileName: pack.hasTrayIconFileName ? pack.trayIconFileName : nil,
			thumbnailDirectPath: pack.hasThumbnailDirectPath ? pack.thumbnailDirectPath : nil,
			thumbnailSHA256: pack.hasThumbnailSha256 ? pack.thumbnailSha256 : nil,
			thumbnailEncSHA256: pack.hasThumbnailEncSha256 ? pack.thumbnailEncSha256 : nil,
			thumbnailHeight: pack.hasThumbnailHeight ? pack.thumbnailHeight : nil,
			thumbnailWidth: pack.hasThumbnailWidth ? pack.thumbnailWidth : nil,
			imageDataHash: pack.hasImageDataHash ? pack.imageDataHash : nil,
			stickerPackSize: pack.hasStickerPackSize ? pack.stickerPackSize : nil,
			origin: pack.hasStickerPackOrigin ? stickerPackOrigin(pack.stickerPackOrigin) : nil
		)
	}

	private static func stickerContent(
		_ sticker: Proto_Message.StickerPackMessage.Sticker
	) -> ReceivedStickerPackStickerContent {
		ReceivedStickerPackStickerContent(
			fileName: sticker.hasFileName ? sticker.fileName : nil,
			isAnimated: sticker.hasIsAnimated ? sticker.isAnimated : nil,
			emojis: sticker.emojis,
			accessibilityLabel: sticker.hasAccessibilityLabel ? sticker.accessibilityLabel : nil,
			isLottie: sticker.hasIsLottie ? sticker.isLottie : nil,
			mimetype: sticker.hasMimetype ? sticker.mimetype : nil
		)
	}

	private static func stickerPackOrigin(
		_ origin: Proto_Message.StickerPackMessage.StickerPackOrigin
	) -> ReceivedStickerPackOrigin {
		switch origin {
		case .firstParty:
			.firstParty
		case .thirdParty:
			.thirdParty
		case .userCreated:
			.userCreated
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}
}
