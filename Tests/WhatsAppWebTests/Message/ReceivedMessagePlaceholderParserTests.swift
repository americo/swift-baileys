import Testing
@testable import WhatsAppWeb

@Suite("Received message placeholder parser")
struct ReceivedMessagePlaceholderParserTests {
	@Test("parses placeholder messages")
	func parsesPlaceholderMessages() throws {
		var placeholder = Proto_Message.PlaceholderMessage()
		placeholder.type = .maskLinkedDevices
		var message = Proto_Message()
		message.placeholderMessage = placeholder

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .placeholder(ReceivedPlaceholderContent(type: .maskLinkedDevices)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent placeholder type")
	func preservesAbsentPlaceholderType() throws {
		var message = Proto_Message()
		message.placeholderMessage = Proto_Message.PlaceholderMessage()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .placeholder(ReceivedPlaceholderContent(type: nil)))
	}
}
