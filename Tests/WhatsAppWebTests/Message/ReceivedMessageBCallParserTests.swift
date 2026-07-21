import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message bcall parser")
struct ReceivedMessageBCallParserTests {
	@Test("parses bcall messages")
	func parsesBCallMessages() throws {
		var bcall = Proto_Message.BCallMessage()
		bcall.sessionID = "call-session-1"
		bcall.mediaType = .video
		bcall.masterKey = Data([1, 2, 3, 4])
		bcall.caption = "Join the call"
		var message = Proto_Message()
		message.bcallMessage = bcall

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .businessCall(ReceivedBusinessCallContent(
			sessionID: "call-session-1",
			mediaType: .video,
			masterKey: Data([1, 2, 3, 4]),
			caption: "Join the call"
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent optional bcall fields")
	func preservesAbsentOptionalBCallFields() throws {
		var message = Proto_Message()
		message.bcallMessage = Proto_Message.BCallMessage()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .businessCall(ReceivedBusinessCallContent(
			sessionID: nil,
			mediaType: nil,
			masterKey: nil,
			caption: nil
		)))
	}
}
