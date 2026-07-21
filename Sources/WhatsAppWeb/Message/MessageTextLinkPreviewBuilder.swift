import Foundation

extension MessageContentBuilder {
	static func textWithLinkPreview(_ content: OutgoingTextContent, quotedRemoteJID: String? = nil) -> Proto_Message {
		var message = text(
			content.text,
			mentions: content.mentions,
			mentionAll: content.mentionAll,
			isForwarded: content.isForwarded,
			forwardingScore: content.forwardingScore,
			quoted: content.quoted,
			quotedRemoteJID: quotedRemoteJID
		)
		guard let preview = content.linkPreview else {
			return message
		}

		var extendedText = message.extendedTextMessage
		extendedText.matchedText = preview.matchedText
		extendedText.title = preview.title
		extendedText.previewType = .none
		if let description = preview.description {
			extendedText.description_p = description
		}
		if let jpegThumbnail = preview.jpegThumbnail {
			extendedText.jpegThumbnail = jpegThumbnail
		}
		if let thumbnail = preview.thumbnail {
			extendedText.thumbnailDirectPath = thumbnail.directPath
			extendedText.mediaKey = thumbnail.mediaKey
			extendedText.mediaKeyTimestamp = thumbnail.mediaKeyTimestamp
			if let width = thumbnail.width {
				extendedText.thumbnailWidth = width
			}
			if let height = thumbnail.height {
				extendedText.thumbnailHeight = height
			}
			if let fileSha256 = thumbnail.fileSha256 {
				extendedText.thumbnailSha256 = fileSha256
			}
			if let fileEncSha256 = thumbnail.fileEncSha256 {
				extendedText.thumbnailEncSha256 = fileEncSha256
			}
		}

		message.extendedTextMessage = extendedText
		return message
	}
}
