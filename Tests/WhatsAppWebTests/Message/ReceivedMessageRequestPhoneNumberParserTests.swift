import Testing
@testable import WhatsAppWeb

@Suite("Received message request phone number parser")
struct ReceivedMessageRequestPhoneNumberParserTests {
	@Test("parses request phone number messages")
	func parsesRequestPhoneNumberMessages() throws {
		var message = Proto_Message()
		message.requestPhoneNumberMessage = Proto_Message.RequestPhoneNumberMessage()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .requestPhoneNumber(ReceivedRequestPhoneNumberContent()))
		#expect(try content.mediaDownloadRequest() == nil)
	}
}
