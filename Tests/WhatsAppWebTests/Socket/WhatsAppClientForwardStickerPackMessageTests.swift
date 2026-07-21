import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward sticker pack messages")
struct WhatsAppClientForwardStickerPackMessageTests {
	@Test("forwards received sticker pack messages through the encrypted send path")
	func forwardsReceivedStickerPackMessagesThroughEncryptedSendPath() async throws {
		let message = try await forwardedMessage(content: .stickerPack(ReceivedStickerPackContent(
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
			origin: .thirdParty
		)))

		#expect(message.hasStickerPackMessage)
		#expect(message.stickerPackMessage.stickerPackID == "pack-123")
		#expect(message.stickerPackMessage.name == "Launch Pack")
		#expect(message.stickerPackMessage.publisher == "SwiftBaileys")
		#expect(message.stickerPackMessage.stickers.count == 1)
		#expect(message.stickerPackMessage.stickers[0].fileName == "sticker-1.webp")
		#expect(message.stickerPackMessage.stickers[0].isAnimated)
		#expect(message.stickerPackMessage.stickers[0].emojis == [":)", "rocket"])
		#expect(message.stickerPackMessage.fileLength == 2048)
		#expect(message.stickerPackMessage.fileSha256 == Data([0x01]))
		#expect(message.stickerPackMessage.fileEncSha256 == Data([0x02]))
		#expect(message.stickerPackMessage.mediaKey == Data([0x03]))
		#expect(message.stickerPackMessage.directPath == "/pack.enc")
		#expect(message.stickerPackMessage.caption == "new stickers")
		#expect(message.stickerPackMessage.packDescription == "A launch themed pack")
		#expect(message.stickerPackMessage.thumbnailDirectPath == "/thumb.enc")
		#expect(message.stickerPackMessage.thumbnailSha256 == Data([0x04]))
		#expect(message.stickerPackMessage.thumbnailEncSha256 == Data([0x05]))
		#expect(message.stickerPackMessage.stickerPackOrigin == .thirdParty)
	}

	private func forwardedMessage(content: ReceivedMessageContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x27]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "STICKERPACK1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDEDSTICKERPACK"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
