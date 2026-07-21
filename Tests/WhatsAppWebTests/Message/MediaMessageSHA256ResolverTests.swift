import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Media message SHA256 resolver")
struct MediaMessageSHA256ResolverTests {
	@Test("returns base64 encoded file SHA256 for direct media content")
	func returnsBase64EncodedFileSHA256ForDirectMediaContent() {
		let hash = Data([0x01, 0x02, 0x03, 0x04])
		let expected = hash.base64EncodedString()

		#expect(MediaMessageSHA256Resolver.base64FileSHA256(for: .image(image(fileSHA256: hash))) == expected)
		#expect(MediaMessageSHA256Resolver.base64FileSHA256(for: .document(document(fileSHA256: hash))) == expected)
		#expect(MediaMessageSHA256Resolver.base64FileSHA256(for: .audio(audio(fileSHA256: hash))) == expected)
		#expect(MediaMessageSHA256Resolver.base64FileSHA256(for: .video(video(fileSHA256: hash))) == expected)
		#expect(MediaMessageSHA256Resolver.base64FileSHA256(for: .sticker(sticker(fileSHA256: hash))) == expected)
	}

	@Test("returns nil for content without media file SHA256")
	func returnsNilForContentWithoutMediaFileSHA256() {
		#expect(MediaMessageSHA256Resolver.base64FileSHA256(for: .text("hello")) == nil)
	}
}

private func image(fileSHA256: Data) -> ReceivedImageContent {
	ReceivedImageContent(
		url: "", directPath: "", mediaKey: Data(), fileEncSHA256: Data(), fileSHA256: fileSHA256,
		fileLength: 0, mediaKeyTimestamp: 0, mimetype: "image/jpeg", caption: nil, jpegThumbnail: nil
	)
}

private func document(fileSHA256: Data) -> ReceivedDocumentContent {
	ReceivedDocumentContent(
		url: "", directPath: "", mediaKey: Data(), fileEncSHA256: Data(), fileSHA256: fileSHA256,
		fileLength: 0, mediaKeyTimestamp: 0, mimetype: "application/pdf", fileName: nil, title: nil, pageCount: nil
	)
}

private func audio(fileSHA256: Data) -> ReceivedAudioContent {
	ReceivedAudioContent(
		url: "", directPath: "", mediaKey: Data(), fileEncSHA256: Data(), fileSHA256: fileSHA256,
		fileLength: 0, mediaKeyTimestamp: 0, mimetype: "audio/ogg", seconds: nil, isVoiceMessage: false,
		waveform: nil
	)
}

private func video(fileSHA256: Data) -> ReceivedVideoContent {
	ReceivedVideoContent(
		url: "", directPath: "", mediaKey: Data(), fileEncSHA256: Data(), fileSHA256: fileSHA256,
		fileLength: 0, mediaKeyTimestamp: 0, mimetype: "video/mp4", caption: nil, seconds: nil, width: nil,
		height: nil, isGIFPlayback: false, jpegThumbnail: nil
	)
}

private func sticker(fileSHA256: Data) -> ReceivedStickerContent {
	ReceivedStickerContent(
		url: "", directPath: "", mediaKey: Data(), fileEncSHA256: Data(), fileSHA256: fileSHA256,
		fileLength: 0, mediaKeyTimestamp: 0, mimetype: "image/webp", width: nil, height: nil, isAnimated: false,
		isAvatar: false, isAISticker: false, isLottie: false, pngThumbnail: nil
	)
}
