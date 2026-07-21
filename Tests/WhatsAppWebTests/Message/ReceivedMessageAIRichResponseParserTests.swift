import Foundation
import SwiftProtobuf
import Testing
@testable import WhatsAppWeb

@Suite("Received message AI rich response parser")
struct ReceivedMessageAIRichResponseParserTests {
	@Test("parses AI rich response messages")
	func parsesAIRichResponseMessages() throws {
		var textSubmessage = Proto_AIRichResponseSubMessage()
		textSubmessage.messageType = .aiRichResponseText
		textSubmessage.messageText = "Here is the answer"
		var codeSubmessage = Proto_AIRichResponseSubMessage()
		codeSubmessage.messageType = .aiRichResponseCode
		var unifiedResponse = Proto_AIRichResponseUnifiedResponse()
		unifiedResponse.data = Data([0x01, 0x02, 0x03])
		var richResponse = Proto_AIRichResponseMessage()
		richResponse.messageType = .aiRichResponseTypeStandard
		richResponse.submessages = [textSubmessage, codeSubmessage]
		richResponse.unifiedResponse = unifiedResponse
		var message = Proto_Message()
		message.richResponseMessage = richResponse

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .aiRichResponse(ReceivedAIRichResponseContent(
			messageType: .standard,
			submessages: [
				ReceivedAIRichResponseSubMessageContent(type: .text, text: "Here is the answer"),
				ReceivedAIRichResponseSubMessageContent(type: .code, text: nil)
			],
			unifiedResponseData: Data([0x01, 0x02, 0x03]),
			serializedBytes: try richResponse.serializedData()
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent AI rich response fields")
	func preservesAbsentAIRichResponseFields() throws {
		var message = Proto_Message()
		message.richResponseMessage = Proto_AIRichResponseMessage()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .aiRichResponse(ReceivedAIRichResponseContent(
			messageType: nil,
			submessages: [],
			unifiedResponseData: nil,
			serializedBytes: try Proto_AIRichResponseMessage().serializedData()
		)))
	}
}
