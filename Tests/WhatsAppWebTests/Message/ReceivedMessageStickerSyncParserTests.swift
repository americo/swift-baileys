import Testing
@testable import WhatsAppWeb

@Suite("Received message sticker sync parser")
struct ReceivedMessageStickerSyncParserTests {
	@Test("parses sticker sync rmr messages")
	func parsesStickerSyncRMRMessages() throws {
		var stickerSync = Proto_Message.StickerSyncRMRMessage()
		stickerSync.filehash = ["hash-a", "hash-b"]
		stickerSync.rmrSource = "sync-source"
		stickerSync.requestTimestamp = 1_717_171_717
		var message = Proto_Message()
		message.stickerSyncRmrMessage = stickerSync

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .stickerSyncRMR(ReceivedStickerSyncRMRContent(
			filehash: ["hash-a", "hash-b"],
			rmrSource: "sync-source",
			requestTimestamp: 1_717_171_717
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent optional sticker sync rmr fields")
	func preservesAbsentOptionalStickerSyncRMRFields() throws {
		var message = Proto_Message()
		message.stickerSyncRmrMessage = Proto_Message.StickerSyncRMRMessage()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .stickerSyncRMR(ReceivedStickerSyncRMRContent(
			filehash: [],
			rmrSource: nil,
			requestTimestamp: nil
		)))
	}
}
