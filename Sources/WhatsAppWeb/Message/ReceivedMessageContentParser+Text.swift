import Foundation

extension ReceivedMessageContentParser {
	static func textContent(_ extendedText: Proto_Message.ExtendedTextMessage) -> ReceivedMessageContent {
		guard extendedText.hasMatchedText else {
			return .text(extendedText.text)
		}

		return .textLinkPreview(ReceivedTextLinkPreviewContent(
			text: extendedText.text,
			matchedText: extendedText.matchedText,
			title: extendedText.hasTitle ? extendedText.title : nil,
			description: extendedText.hasDescription_p ? extendedText.description_p : nil,
			jpegThumbnail: extendedText.hasJpegThumbnail ? extendedText.jpegThumbnail : nil,
			thumbnail: linkPreviewThumbnailContent(extendedText)
		))
	}

	private static func linkPreviewThumbnailContent(
		_ extendedText: Proto_Message.ExtendedTextMessage
	) -> ReceivedTextLinkPreviewThumbnailContent? {
		guard extendedText.hasThumbnailDirectPath, extendedText.hasMediaKey else {
			return nil
		}

		return ReceivedTextLinkPreviewThumbnailContent(
			directPath: extendedText.thumbnailDirectPath,
			mediaKey: extendedText.mediaKey,
			mediaKeyTimestamp: extendedText.hasMediaKeyTimestamp ? extendedText.mediaKeyTimestamp : nil,
			width: extendedText.hasThumbnailWidth ? extendedText.thumbnailWidth : nil,
			height: extendedText.hasThumbnailHeight ? extendedText.thumbnailHeight : nil,
			fileSha256: extendedText.hasThumbnailSha256 ? extendedText.thumbnailSha256 : nil,
			fileEncSha256: extendedText.hasThumbnailEncSha256 ? extendedText.thumbnailEncSha256 : nil
		)
	}
}
