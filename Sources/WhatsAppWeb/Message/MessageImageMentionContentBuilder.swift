extension MessageContentBuilder {
	static func imageWithMentions(
		_ content: Proto_Message,
		mentions: [String],
		mentionAll: Bool,
		ephemeralExpiration: UInt32? = nil
	) -> Proto_Message {
		guard content.hasImageMessage, !mentions.isEmpty || mentionAll || ephemeralExpiration != nil else {
			return content
		}

		var message = content
		var image = message.imageMessage
		var contextInfo = image.contextInfo
		contextInfo.mentionedJid = mentions
		if mentionAll {
			contextInfo.nonJidMentions = 1
		}
		if let ephemeralExpiration {
			contextInfo.expiration = ephemeralExpiration
		}

		image.contextInfo = contextInfo
		message.imageMessage = image
		return message
	}

	static func documentWithMentions(
		_ content: Proto_Message,
		mentions: [String],
		mentionAll: Bool,
		ephemeralExpiration: UInt32? = nil
	) -> Proto_Message {
		guard content.hasDocumentMessage, !mentions.isEmpty || mentionAll || ephemeralExpiration != nil else {
			return content
		}

		var message = content
		var document = message.documentMessage
		var contextInfo = document.contextInfo
		contextInfo.mentionedJid = mentions
		if mentionAll {
			contextInfo.nonJidMentions = 1
		}
		if let ephemeralExpiration {
			contextInfo.expiration = ephemeralExpiration
		}

		document.contextInfo = contextInfo
		message.documentMessage = document
		return message
	}

	static func videoWithMentions(
		_ content: Proto_Message,
		mentions: [String],
		mentionAll: Bool,
		ephemeralExpiration: UInt32? = nil
	) -> Proto_Message {
		guard content.hasVideoMessage, !mentions.isEmpty || mentionAll || ephemeralExpiration != nil else {
			return content
		}

		var message = content
		var video = message.videoMessage
		var contextInfo = video.contextInfo
		contextInfo.mentionedJid = mentions
		if mentionAll {
			contextInfo.nonJidMentions = 1
		}
		if let ephemeralExpiration {
			contextInfo.expiration = ephemeralExpiration
		}

		video.contextInfo = contextInfo
		message.videoMessage = video
		return message
	}
}
