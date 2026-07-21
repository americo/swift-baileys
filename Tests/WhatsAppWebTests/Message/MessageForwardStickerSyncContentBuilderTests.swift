import Testing
@testable import WhatsAppWeb

@Suite("Message forward sticker sync content builder")
struct MessageForwardStickerSyncContentBuilderTests {
	@Test("forwards sticker sync rmr messages as pass-through content")
	func forwardsStickerSyncRMRMessagesAsPassThroughContent() throws {
		var stickerSync = Proto_Message.StickerSyncRMRMessage()
		stickerSync.filehash = ["hash-a", "hash-b"]
		stickerSync.rmrSource = "rmr-source"
		stickerSync.requestTimestamp = 1_717_171_717
		var source = Proto_Message()
		source.stickerSyncRmrMessage = stickerSync

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasStickerSyncRmrMessage)
		#expect(message.stickerSyncRmrMessage.filehash == ["hash-a", "hash-b"])
		#expect(message.stickerSyncRmrMessage.rmrSource == "rmr-source")
		#expect(message.stickerSyncRmrMessage.requestTimestamp == 1_717_171_717)
	}
}
