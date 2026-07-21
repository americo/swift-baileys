enum ForwardMediaMessageMapper {
	static func image(from content: ReceivedImageContent) -> Proto_Message.ImageMessage {
		var message = Proto_Message.ImageMessage()
		message.url = content.url
		message.directPath = content.directPath
		message.mediaKey = content.mediaKey
		message.fileEncSha256 = content.fileEncSHA256
		message.fileSha256 = content.fileSHA256
		message.fileLength = content.fileLength
		message.mediaKeyTimestamp = content.mediaKeyTimestamp
		message.mimetype = content.mimetype
		if let caption = content.caption {
			message.caption = caption
		}
		if let jpegThumbnail = content.jpegThumbnail {
			message.jpegThumbnail = jpegThumbnail
		}
		return message
	}

	static func document(from content: ReceivedDocumentContent) -> Proto_Message.DocumentMessage {
		var message = Proto_Message.DocumentMessage()
		message.url = content.url
		message.directPath = content.directPath
		message.mediaKey = content.mediaKey
		message.fileEncSha256 = content.fileEncSHA256
		message.fileSha256 = content.fileSHA256
		message.fileLength = content.fileLength
		message.mediaKeyTimestamp = content.mediaKeyTimestamp
		message.mimetype = content.mimetype
		if let fileName = content.fileName {
			message.fileName = fileName
		}
		if let title = content.title {
			message.title = title
		}
		if let pageCount = content.pageCount {
			message.pageCount = pageCount
		}
		return message
	}

	static func audio(from content: ReceivedAudioContent) -> Proto_Message.AudioMessage {
		var message = Proto_Message.AudioMessage()
		message.url = content.url
		message.directPath = content.directPath
		message.mediaKey = content.mediaKey
		message.fileEncSha256 = content.fileEncSHA256
		message.fileSha256 = content.fileSHA256
		message.fileLength = content.fileLength
		message.mediaKeyTimestamp = content.mediaKeyTimestamp
		message.mimetype = content.mimetype
		message.ptt = content.isVoiceMessage
		if let seconds = content.seconds {
			message.seconds = seconds
		}
		if let waveform = content.waveform {
			message.waveform = waveform
		}
		return message
	}

	static func video(from content: ReceivedVideoContent) -> Proto_Message.VideoMessage {
		var message = Proto_Message.VideoMessage()
		message.url = content.url
		message.directPath = content.directPath
		message.mediaKey = content.mediaKey
		message.fileEncSha256 = content.fileEncSHA256
		message.fileSha256 = content.fileSHA256
		message.fileLength = content.fileLength
		message.mediaKeyTimestamp = content.mediaKeyTimestamp
		message.mimetype = content.mimetype
		message.gifPlayback = content.isGIFPlayback
		if let caption = content.caption {
			message.caption = caption
		}
		if let seconds = content.seconds {
			message.seconds = seconds
		}
		if let width = content.width {
			message.width = width
		}
		if let height = content.height {
			message.height = height
		}
		if let jpegThumbnail = content.jpegThumbnail {
			message.jpegThumbnail = jpegThumbnail
		}
		return message
	}

	static func sticker(from content: ReceivedStickerContent) -> Proto_Message.StickerMessage {
		var message = Proto_Message.StickerMessage()
		message.url = content.url
		message.directPath = content.directPath
		message.mediaKey = content.mediaKey
		message.fileEncSha256 = content.fileEncSHA256
		message.fileSha256 = content.fileSHA256
		message.fileLength = content.fileLength
		message.mediaKeyTimestamp = content.mediaKeyTimestamp
		message.mimetype = content.mimetype
		message.isAnimated = content.isAnimated
		message.isAvatar = content.isAvatar
		message.isAiSticker = content.isAISticker
		message.isLottie = content.isLottie
		if let width = content.width {
			message.width = width
		}
		if let height = content.height {
			message.height = height
		}
		if let pngThumbnail = content.pngThumbnail {
			message.pngThumbnail = pngThumbnail
		}
		return message
	}

	static func location(from content: ReceivedLocationContent) -> Proto_Message.LocationMessage {
		var message = Proto_Message.LocationMessage()
		message.degreesLatitude = content.latitude
		message.degreesLongitude = content.longitude
		if let name = content.name {
			message.name = name
		}
		if let address = content.address {
			message.address = address
		}
		if let url = content.url {
			message.url = url
		}
		if let accuracyInMeters = content.accuracyInMeters {
			message.accuracyInMeters = accuracyInMeters
		}
		if let comment = content.comment {
			message.comment = comment
		}
		if let jpegThumbnail = content.jpegThumbnail {
			message.jpegThumbnail = jpegThumbnail
		}
		return message
	}
}
