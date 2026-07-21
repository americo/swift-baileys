import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message sticker pack parser")
struct ReceivedMessageStickerPackParserTests {
	@Test("parses sticker pack messages")
	func parsesStickerPackMessages() throws {
		var sticker = Proto_Message.StickerPackMessage.Sticker()
		sticker.fileName = "sticker-1.webp"
		sticker.isAnimated = true
		sticker.emojis = [":)", "rocket"]
		sticker.accessibilityLabel = "launch"
		sticker.isLottie = false
		sticker.mimetype = "image/webp"
		var pack = Proto_Message.StickerPackMessage()
		pack.stickerPackID = "pack-123"
		pack.name = "Launch Pack"
		pack.publisher = "SwiftBaileys"
		pack.stickers = [sticker]
		pack.fileLength = 2048
		pack.fileSha256 = Data([0x01])
		pack.fileEncSha256 = Data([0x02])
		pack.mediaKey = Data([0x03])
		pack.directPath = "/pack.enc"
		pack.caption = "new stickers"
		pack.packDescription = "A launch themed pack"
		pack.mediaKeyTimestamp = 1_800_000_000
		pack.trayIconFileName = "tray.webp"
		pack.thumbnailDirectPath = "/thumb.enc"
		pack.thumbnailSha256 = Data([0x04])
		pack.thumbnailEncSha256 = Data([0x05])
		pack.thumbnailHeight = 96
		pack.thumbnailWidth = 128
		pack.imageDataHash = "image-hash"
		pack.stickerPackSize = 8
		pack.stickerPackOrigin = .userCreated
		var message = Proto_Message()
		message.stickerPackMessage = pack

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .stickerPack(ReceivedStickerPackContent(
			id: "pack-123",
			name: "Launch Pack",
			publisher: "SwiftBaileys",
			stickers: [
				ReceivedStickerPackStickerContent(
					fileName: "sticker-1.webp",
					isAnimated: true,
					emojis: [":)", "rocket"],
					accessibilityLabel: "launch",
					isLottie: false,
					mimetype: "image/webp"
				)
			],
			fileLength: 2048,
			fileSHA256: Data([0x01]),
			fileEncSHA256: Data([0x02]),
			mediaKey: Data([0x03]),
			directPath: "/pack.enc",
			caption: "new stickers",
			packDescription: "A launch themed pack",
			mediaKeyTimestamp: 1_800_000_000,
			trayIconFileName: "tray.webp",
			thumbnailDirectPath: "/thumb.enc",
			thumbnailSHA256: Data([0x04]),
			thumbnailEncSHA256: Data([0x05]),
			thumbnailHeight: 96,
			thumbnailWidth: 128,
			imageDataHash: "image-hash",
			stickerPackSize: 8,
			origin: .userCreated
		)))
		let request = try #require(try content.mediaDownloadRequest())
		#expect(request.url.absoluteString == "https://mmg.whatsapp.net/thumb.enc")
		#expect(request.mediaKey == Data([0x03]))
		#expect(request.mediaType == .thumbnailImage)
		#expect(request.fileEncSHA256 == Data([0x05]))
		#expect(request.fileSHA256 == Data([0x04]))
	}

	@Test("preserves absent optional sticker pack fields")
	func preservesAbsentOptionalStickerPackFields() throws {
		var message = Proto_Message()
		message.stickerPackMessage = Proto_Message.StickerPackMessage()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .stickerPack(ReceivedStickerPackContent(
			id: nil,
			name: nil,
			publisher: nil,
			stickers: [],
			fileLength: nil,
			fileSHA256: nil,
			fileEncSHA256: nil,
			mediaKey: nil,
			directPath: nil,
			caption: nil,
			packDescription: nil,
			mediaKeyTimestamp: nil,
			trayIconFileName: nil,
			thumbnailDirectPath: nil,
			thumbnailSHA256: nil,
			thumbnailEncSHA256: nil,
			thumbnailHeight: nil,
			thumbnailWidth: nil,
			imageDataHash: nil,
			stickerPackSize: nil,
			origin: nil
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}
}
