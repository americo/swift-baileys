enum MessageMediaContent: Equatable, Sendable {
	case document(Proto_Message.DocumentMessage)
	case image(Proto_Message.ImageMessage)
	case video(Proto_Message.VideoMessage)
	case audio(Proto_Message.AudioMessage)
	case sticker(Proto_Message.StickerMessage)
}

enum MessageMediaContentError: Error, Equatable, Sendable {
	case notMediaMessage
}

enum MessageMediaContentResolver {
	static func assertMediaContent(_ message: Proto_Message) throws -> MessageMediaContent {
		let content = MessageContentNormalizer.extractedContent(message)
		if content.hasDocumentMessage {
			return .document(content.documentMessage)
		}

		if content.hasImageMessage {
			return .image(content.imageMessage)
		}

		if content.hasVideoMessage {
			return .video(content.videoMessage)
		}

		if content.hasAudioMessage {
			return .audio(content.audioMessage)
		}

		if content.hasStickerMessage {
			return .sticker(content.stickerMessage)
		}

		throw MessageMediaContentError.notMediaMessage
	}
}
