import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message history notice parser")
struct ReceivedMessageHistoryNoticeParserTests {
	@Test("parses message history bundles")
	func parsesMessageHistoryBundles() throws {
		var metadata = Proto_Message.MessageHistoryMetadata()
		metadata.historyReceivers = ["111@s.whatsapp.net", "222@s.whatsapp.net"]
		metadata.oldestMessageTimestamp = 1_717_700_000
		metadata.messageCount = 42
		var bundle = Proto_Message.MessageHistoryBundle()
		bundle.mimetype = "application/octet-stream"
		bundle.fileSha256 = Data([0x01])
		bundle.mediaKey = Data([0x02])
		bundle.fileEncSha256 = Data([0x03])
		bundle.directPath = "/v/t62.7118-24/history-bundle.enc"
		bundle.mediaKeyTimestamp = 1_800_000_000
		bundle.messageHistoryMetadata = metadata
		var message = Proto_Message()
		message.messageHistoryBundle = bundle

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .messageHistoryBundle(ReceivedMessageHistoryBundleContent(
			mimetype: "application/octet-stream",
			fileSHA256: Data([0x01]),
			mediaKey: Data([0x02]),
			fileEncSHA256: Data([0x03]),
			directPath: "/v/t62.7118-24/history-bundle.enc",
			mediaKeyTimestamp: 1_800_000_000,
			metadata: ReceivedMessageHistoryMetadataContent(
				historyReceivers: ["111@s.whatsapp.net", "222@s.whatsapp.net"],
				oldestMessageTimestamp: 1_717_700_000,
				messageCount: 42
			)
		)))
		let request = try #require(try content.mediaDownloadRequest())
		#expect(request.url.absoluteString == "https://mmg.whatsapp.net/v/t62.7118-24/history-bundle.enc")
		#expect(request.mediaKey == Data([0x02]))
		#expect(request.mediaType == .mdMessageHistory)
		#expect(request.fileEncSHA256 == Data([0x03]))
		#expect(request.fileSHA256 == Data([0x01]))
	}

	@Test("preserves absent message history bundle fields")
	func preservesAbsentMessageHistoryBundleFields() throws {
		var message = Proto_Message()
		message.messageHistoryBundle = Proto_Message.MessageHistoryBundle()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .messageHistoryBundle(ReceivedMessageHistoryBundleContent(
			mimetype: nil,
			fileSHA256: nil,
			mediaKey: nil,
			fileEncSHA256: nil,
			directPath: nil,
			mediaKeyTimestamp: nil,
			metadata: nil
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses message history notices")
	func parsesMessageHistoryNotices() throws {
		var metadata = Proto_Message.MessageHistoryMetadata()
		metadata.historyReceivers = ["111@s.whatsapp.net", "222@s.whatsapp.net"]
		metadata.oldestMessageTimestamp = 1_717_700_000
		metadata.messageCount = 42
		var notice = Proto_Message.MessageHistoryNotice()
		notice.messageHistoryMetadata = metadata
		var message = Proto_Message()
		message.messageHistoryNotice = notice

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .messageHistoryNotice(ReceivedMessageHistoryNoticeContent(
			metadata: ReceivedMessageHistoryMetadataContent(
				historyReceivers: ["111@s.whatsapp.net", "222@s.whatsapp.net"],
				oldestMessageTimestamp: 1_717_700_000,
				messageCount: 42
			)
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent message history metadata")
	func preservesAbsentMessageHistoryMetadata() throws {
		var message = Proto_Message()
		message.messageHistoryNotice = Proto_Message.MessageHistoryNotice()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .messageHistoryNotice(ReceivedMessageHistoryNoticeContent(metadata: nil)))
	}
}
