import Foundation

public enum OutgoingMediaContent: Equatable, Sendable {
	case image(OutgoingImageContent)
	case video(OutgoingVideoContent)
	case audio(OutgoingAudioContent)
	case document(OutgoingDocumentContent)

	fileprivate var uploadType: MediaType {
		switch self {
		case .image: .image
		case .video: .video
		case .audio: .audio
		case .document: .document
		}
	}
}

extension WhatsAppClient {
	/// Uploads the bytes and sends them, optionally replying to a message and mentioning people.
	/// Reaches groups as well as one-to-one chats.
	public func sendMediaMessage(
		to destinationJID: String,
		data: Data,
		media: OutgoingMediaContent,
		mentions: [String] = [],
		quoted: OutgoingQuotedTextContent? = nil,
		messageID: String? = nil
	) async throws -> String {
		let uploaded = try await uploadMedia(data, mediaType: media.uploadType)
		let message = MessageContentBuilder.withContext(
			Self.uploadedMessage(media, uploaded: uploaded, timestamp: mediaKeyTimestamp()),
			mentions: mentions,
			quoted: quoted,
			quotedRemoteJID: quoted?.chatJID == destinationJID ? nil : quoted?.chatJID
		)
		return try await sendResolvedMessage(to: destinationJID, message: message, messageID: messageID)
	}

	private static func uploadedMessage(
		_ media: OutgoingMediaContent,
		uploaded: UploadedMedia,
		timestamp: Int64
	) -> Proto_Message {
		let url = uploaded.result.mediaURL
		let directPath = uploaded.result.directPath
		let encrypted = uploaded.encryptedMedia
		let fileLength = UInt64(encrypted.fileLength)
		switch media {
		case .image(let image):
			var message = MessageContentBuilder.uploadedImage(UploadedImageContent(
				url: url, directPath: directPath, mediaKey: uploaded.mediaKey,
				fileEncSha256: encrypted.fileEncSha256, fileSha256: encrypted.fileSha256,
				fileLength: fileLength, mediaKeyTimestamp: timestamp,
				mimetype: image.mimetype, caption: image.caption, jpegThumbnail: image.jpegThumbnail
			))
			if let width = image.width { message.imageMessage.width = width }
			if let height = image.height { message.imageMessage.height = height }
			return message
		case .video(let video):
			return MessageContentBuilder.uploadedVideo(UploadedVideoContent(
				url: url, directPath: directPath, mediaKey: uploaded.mediaKey,
				fileEncSha256: encrypted.fileEncSha256, fileSha256: encrypted.fileSha256,
				fileLength: fileLength, mediaKeyTimestamp: timestamp, video: video
			))
		case .audio(let audio):
			return MessageContentBuilder.uploadedAudio(UploadedAudioContent(
				url: url, directPath: directPath, mediaKey: uploaded.mediaKey,
				fileEncSha256: encrypted.fileEncSha256, fileSha256: encrypted.fileSha256,
				fileLength: fileLength, mediaKeyTimestamp: timestamp, audio: audio
			))
		case .document(let document):
			return MessageContentBuilder.uploadedDocument(UploadedDocumentContent(
				url: url, directPath: directPath, mediaKey: uploaded.mediaKey,
				fileEncSha256: encrypted.fileEncSha256, fileSha256: encrypted.fileSha256,
				fileLength: fileLength, mediaKeyTimestamp: timestamp, document: document
			))
		}
	}
}

extension MessageContentBuilder {
	/// Adds mentions and the replied-to message to a media message.
	static func withContext(
		_ content: Proto_Message,
		mentions: [String],
		quoted: OutgoingQuotedTextContent?,
		quotedRemoteJID: String?
	) -> Proto_Message {
		guard !mentions.isEmpty || quoted != nil else { return content }

		func merged(_ existing: Proto_ContextInfo) -> Proto_ContextInfo {
			var contextInfo = existing
			contextInfo.mentionedJid = mentions
			if let quoted {
				contextInfo.stanzaID = quoted.messageID
				contextInfo.participant = quoted.participantJID
				contextInfo.quotedMessage = MessageContentBuilder.text(quoted.text)
				if let quotedRemoteJID {
					contextInfo.remoteJid = quotedRemoteJID
				}
			}
			return contextInfo
		}

		var message = content
		if message.hasImageMessage {
			message.imageMessage.contextInfo = merged(message.imageMessage.contextInfo)
		} else if message.hasVideoMessage {
			message.videoMessage.contextInfo = merged(message.videoMessage.contextInfo)
		} else if message.hasAudioMessage {
			message.audioMessage.contextInfo = merged(message.audioMessage.contextInfo)
		} else if message.hasDocumentMessage {
			message.documentMessage.contextInfo = merged(message.documentMessage.contextInfo)
		}
		return message
	}
}
