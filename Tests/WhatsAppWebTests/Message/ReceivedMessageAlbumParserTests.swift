import Testing
@testable import WhatsAppWeb

@Suite("Received message album parser")
struct ReceivedMessageAlbumParserTests {
	@Test("parses album messages")
	func parsesAlbumMessages() throws {
		var album = Proto_Message.AlbumMessage()
		album.expectedImageCount = 3
		album.expectedVideoCount = 2
		var message = Proto_Message()
		message.albumMessage = album

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .album(ReceivedAlbumContent(
			expectedImageCount: 3,
			expectedVideoCount: 2
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent optional album counts")
	func preservesAbsentOptionalAlbumCounts() throws {
		var message = Proto_Message()
		message.albumMessage = Proto_Message.AlbumMessage()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .album(ReceivedAlbumContent(
			expectedImageCount: nil,
			expectedVideoCount: nil
		)))
	}
}
