import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message link preview parser")
struct ReceivedMessageLinkPreviewParserTests {
	@Test("parses extended text link previews")
	func parsesExtendedTextLinkPreviews() throws {
		let message = MessageContentBuilder.textWithLinkPreview(OutgoingTextContent(
			text: "Read https://example.com now",
			linkPreview: OutgoingLinkPreviewContent(
				matchedText: "https://example.com",
				title: "Example title",
				description: "Example description",
				jpegThumbnail: Data([0x01, 0x02, 0x03]),
				thumbnail: OutgoingLinkPreviewThumbnailContent(
					directPath: "/v/t62.7118-24/link",
					mediaKey: Data([0x04, 0x05, 0x06]),
					mediaKeyTimestamp: 1_717_000_000,
					width: 640,
					height: 360,
					fileSha256: Data([0x07, 0x08, 0x09]),
					fileEncSha256: Data([0x0a, 0x0b, 0x0c])
				)
			)
		))

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .textLinkPreview(ReceivedTextLinkPreviewContent(
			text: "Read https://example.com now",
			matchedText: "https://example.com",
			title: "Example title",
			description: "Example description",
			jpegThumbnail: Data([0x01, 0x02, 0x03]),
			thumbnail: ReceivedTextLinkPreviewThumbnailContent(
				directPath: "/v/t62.7118-24/link",
				mediaKey: Data([0x04, 0x05, 0x06]),
				mediaKeyTimestamp: 1_717_000_000,
				width: 640,
				height: 360,
				fileSha256: Data([0x07, 0x08, 0x09]),
				fileEncSha256: Data([0x0a, 0x0b, 0x0c])
			)
		)))
	}
}
