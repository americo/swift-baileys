import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message lottie sticker parser")
struct ReceivedMessageLottieStickerParserTests {
	@Test("parses lottie sticker messages as sticker media")
	func parsesLottieStickerMessagesAsStickerMedia() throws {
		let mediaKey = try hexData("606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f")
		let fileEncSHA256 = try hexData("c1f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d")
		let fileSHA256 = try hexData("d207adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce")
		var sticker = Proto_Message.StickerMessage()
		sticker.url = "https://mmg.whatsapp.net/o1/v/t62.7161-24/lottie"
		sticker.directPath = "/v/t62.7161-24/lottie.enc?ccb=11-4&oh=01"
		sticker.mediaKey = mediaKey
		sticker.fileEncSha256 = fileEncSHA256
		sticker.fileSha256 = fileSHA256
		sticker.fileLength = 2048
		sticker.mediaKeyTimestamp = 1_700_222_333
		sticker.mimetype = "application/was"
		sticker.width = 512
		sticker.height = 512
		sticker.isAnimated = true
		sticker.isLottie = true
		var inner = Proto_Message()
		inner.stickerMessage = sticker
		var envelope = Proto_Message.FutureProofMessage()
		envelope.message = inner
		var message = Proto_Message()
		message.lottieStickerMessage = envelope

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .sticker(ReceivedStickerContent(
			url: "https://mmg.whatsapp.net/o1/v/t62.7161-24/lottie",
			directPath: "/v/t62.7161-24/lottie.enc?ccb=11-4&oh=01",
			mediaKey: mediaKey,
			fileEncSHA256: fileEncSHA256,
			fileSHA256: fileSHA256,
			fileLength: 2048,
			mediaKeyTimestamp: 1_700_222_333,
			mimetype: "application/was",
			width: 512,
			height: 512,
			isAnimated: true,
			isAvatar: false,
			isAISticker: false,
			isLottie: true,
			pngThumbnail: nil
		)))
		#expect(try content.mediaDownloadRequest()?.mediaType == .sticker)
	}
}
