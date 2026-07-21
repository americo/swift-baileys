extension ReceivedMessageContentParser {
	static func imageContent(_ image: Proto_Message.ImageMessage) -> ReceivedImageContent {
		ReceivedImageContent(
			url: image.url,
			directPath: image.directPath,
			mediaKey: image.mediaKey,
			fileEncSHA256: image.fileEncSha256,
			fileSHA256: image.fileSha256,
			fileLength: image.fileLength,
			mediaKeyTimestamp: image.mediaKeyTimestamp,
			mimetype: image.mimetype,
			caption: image.hasCaption ? image.caption : nil,
			jpegThumbnail: image.hasJpegThumbnail ? image.jpegThumbnail : nil
		)
	}

	static func documentContent(_ document: Proto_Message.DocumentMessage) -> ReceivedDocumentContent {
		ReceivedDocumentContent(
			url: document.url,
			directPath: document.directPath,
			mediaKey: document.mediaKey,
			fileEncSHA256: document.fileEncSha256,
			fileSHA256: document.fileSha256,
			fileLength: document.fileLength,
			mediaKeyTimestamp: document.mediaKeyTimestamp,
			mimetype: document.mimetype,
			fileName: document.hasFileName ? document.fileName : nil,
			title: document.hasTitle ? document.title : nil,
			pageCount: document.hasPageCount ? document.pageCount : nil
		)
	}

	static func audioContent(_ audio: Proto_Message.AudioMessage) -> ReceivedAudioContent {
		ReceivedAudioContent(
			url: audio.url,
			directPath: audio.directPath,
			mediaKey: audio.mediaKey,
			fileEncSHA256: audio.fileEncSha256,
			fileSHA256: audio.fileSha256,
			fileLength: audio.fileLength,
			mediaKeyTimestamp: audio.mediaKeyTimestamp,
			mimetype: audio.mimetype,
			seconds: audio.hasSeconds ? audio.seconds : nil,
			isVoiceMessage: audio.ptt,
			waveform: audio.hasWaveform ? audio.waveform : nil
		)
	}

	static func locationContent(_ location: Proto_Message.LocationMessage) -> ReceivedLocationContent {
		ReceivedLocationContent(
			latitude: location.degreesLatitude,
			longitude: location.degreesLongitude,
			name: location.hasName ? location.name : nil,
			address: location.hasAddress ? location.address : nil,
			url: location.hasURL ? location.url : nil,
			accuracyInMeters: location.hasAccuracyInMeters ? location.accuracyInMeters : nil,
			comment: location.hasComment ? location.comment : nil,
			jpegThumbnail: location.hasJpegThumbnail ? location.jpegThumbnail : nil
		)
	}

	static func videoContent(_ video: Proto_Message.VideoMessage) -> ReceivedVideoContent {
		ReceivedVideoContent(
			url: video.url,
			directPath: video.directPath,
			mediaKey: video.mediaKey,
			fileEncSHA256: video.fileEncSha256,
			fileSHA256: video.fileSha256,
			fileLength: video.fileLength,
			mediaKeyTimestamp: video.mediaKeyTimestamp,
			mimetype: video.mimetype,
			caption: video.hasCaption ? video.caption : nil,
			seconds: video.hasSeconds ? video.seconds : nil,
			width: video.hasWidth ? video.width : nil,
			height: video.hasHeight ? video.height : nil,
			isGIFPlayback: video.gifPlayback,
			jpegThumbnail: video.hasJpegThumbnail ? video.jpegThumbnail : nil
		)
	}

	static func stickerContent(_ sticker: Proto_Message.StickerMessage) -> ReceivedStickerContent {
		ReceivedStickerContent(
			url: sticker.url,
			directPath: sticker.directPath,
			mediaKey: sticker.mediaKey,
			fileEncSHA256: sticker.fileEncSha256,
			fileSHA256: sticker.fileSha256,
			fileLength: sticker.fileLength,
			mediaKeyTimestamp: sticker.mediaKeyTimestamp,
			mimetype: sticker.mimetype,
			width: sticker.hasWidth ? sticker.width : nil,
			height: sticker.hasHeight ? sticker.height : nil,
			isAnimated: sticker.isAnimated,
			isAvatar: sticker.isAvatar,
			isAISticker: sticker.isAiSticker,
			isLottie: sticker.isLottie,
			pngThumbnail: sticker.hasPngThumbnail ? sticker.pngThumbnail : nil
		)
	}
}
