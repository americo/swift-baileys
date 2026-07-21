import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Media file extension resolver")
struct MediaFileExtensionResolverTests {
	@Test("resolves media extensions from mimetype subtypes")
	func resolvesMediaExtensionsFromMimetypeSubtypes() {
		#expect(MediaFileExtensionResolver.fileExtension(for: .image(image(mimetype: "image/png"))) == ".png")
		#expect(MediaFileExtensionResolver.fileExtension(for: .document(document(mimetype: "application/pdf"))) == ".pdf")
		#expect(MediaFileExtensionResolver.fileExtension(for: .video(video(mimetype: "video/mp4"))) == ".mp4")
		#expect(MediaFileExtensionResolver.fileExtension(for: .sticker(sticker(mimetype: "application/was"))) == ".was")
	}

	@Test("ignores mimetype parameters like Baileys")
	func ignoresMimetypeParametersLikeBaileys() {
		#expect(MediaFileExtensionResolver.fileExtension(for: .audio(audio(mimetype: "audio/ogg; codecs=opus"))) == ".ogg")
	}

	@Test("uses jpeg for location live location and product messages")
	func usesJpegForLocationLiveLocationAndProductMessages() {
		#expect(MediaFileExtensionResolver.fileExtension(for: .location(location())) == ".jpeg")
		#expect(MediaFileExtensionResolver.fileExtension(for: .liveLocation(liveLocation())) == ".jpeg")
		#expect(MediaFileExtensionResolver.fileExtension(for: .product(product())) == ".jpeg")
	}

	@Test("returns nil for non media messages")
	func returnsNilForNonMediaMessages() {
		#expect(MediaFileExtensionResolver.fileExtension(for: .text("hello")) == nil)
	}
}

private func image(mimetype: String) -> ReceivedImageContent {
	ReceivedImageContent(
		url: "", directPath: "", mediaKey: Data(), fileEncSHA256: Data(), fileSHA256: Data(),
		fileLength: 0, mediaKeyTimestamp: 0, mimetype: mimetype, caption: nil, jpegThumbnail: nil
	)
}

private func document(mimetype: String) -> ReceivedDocumentContent {
	ReceivedDocumentContent(
		url: "", directPath: "", mediaKey: Data(), fileEncSHA256: Data(), fileSHA256: Data(),
		fileLength: 0, mediaKeyTimestamp: 0, mimetype: mimetype, fileName: nil, title: nil, pageCount: nil
	)
}

private func audio(mimetype: String) -> ReceivedAudioContent {
	ReceivedAudioContent(
		url: "", directPath: "", mediaKey: Data(), fileEncSHA256: Data(), fileSHA256: Data(),
		fileLength: 0, mediaKeyTimestamp: 0, mimetype: mimetype, seconds: nil, isVoiceMessage: false, waveform: nil
	)
}

private func video(mimetype: String) -> ReceivedVideoContent {
	ReceivedVideoContent(
		url: "", directPath: "", mediaKey: Data(), fileEncSHA256: Data(), fileSHA256: Data(),
		fileLength: 0, mediaKeyTimestamp: 0, mimetype: mimetype, caption: nil, seconds: nil, width: nil,
		height: nil, isGIFPlayback: false, jpegThumbnail: nil
	)
}

private func sticker(mimetype: String) -> ReceivedStickerContent {
	ReceivedStickerContent(
		url: "", directPath: "", mediaKey: Data(), fileEncSHA256: Data(), fileSHA256: Data(),
		fileLength: 0, mediaKeyTimestamp: 0, mimetype: mimetype, width: nil, height: nil, isAnimated: false,
		isAvatar: false, isAISticker: false, isLottie: false, pngThumbnail: nil
	)
}

private func location() -> ReceivedLocationContent {
	ReceivedLocationContent(
		latitude: 0, longitude: 0, name: nil, address: nil, url: nil, accuracyInMeters: nil,
		comment: nil, jpegThumbnail: nil
	)
}

private func liveLocation() -> ReceivedLiveLocationContent {
	ReceivedLiveLocationContent(
		latitude: 0, longitude: 0, accuracyInMeters: nil, speedInMetersPerSecond: nil,
		degreesClockwiseFromMagneticNorth: nil, caption: nil, sequenceNumber: nil, timeOffsetSeconds: nil,
		jpegThumbnail: nil
	)
}

private func product() -> ReceivedProductContent {
	ReceivedProductContent(product: nil, businessOwnerJID: nil, catalog: nil, body: nil, footer: nil)
}
