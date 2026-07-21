import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message call and chat parser")
struct ReceivedMessageCallChatParserTests {
	@Test("parses call messages")
	func parsesCallMessages() throws {
		let callKey = Data([0x01, 0x02])
		let conversionData = Data([0x03, 0x04])
		let ctwaPayload = Data([0x05, 0x06])
		var call = Proto_Message.Call()
		call.callKey = callKey
		call.conversionSource = "ad"
		call.conversionData = conversionData
		call.conversionDelaySeconds = 7
		call.ctwaSignals = "signals"
		call.ctwaPayload = ctwaPayload
		call.nativeFlowCallButtonPayload = "{\"call\":true}"
		call.deeplinkPayload = "whatsapp://call"
		var message = Proto_Message()
		message.call = call

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .call(ReceivedCallContent(
			callKey: callKey,
			conversionSource: "ad",
			conversionData: conversionData,
			conversionDelaySeconds: 7,
			ctwaSignals: "signals",
			ctwaPayload: ctwaPayload,
			nativeFlowCallButtonPayload: "{\"call\":true}",
			deeplinkPayload: "whatsapp://call"
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent call fields")
	func preservesAbsentCallFields() throws {
		var message = Proto_Message()
		message.call = Proto_Message.Call()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .call(ReceivedCallContent(
			callKey: nil,
			conversionSource: nil,
			conversionData: nil,
			conversionDelaySeconds: nil,
			ctwaSignals: nil,
			ctwaPayload: nil,
			nativeFlowCallButtonPayload: nil,
			deeplinkPayload: nil
		)))
	}

	@Test("parses chat messages")
	func parsesChatMessages() throws {
		var chat = Proto_Message.Chat()
		chat.displayName = "Support"
		chat.id = "12025550123@s.whatsapp.net"
		var message = Proto_Message()
		message.chat = chat

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .chat(ReceivedChatContent(
			displayName: "Support",
			id: "12025550123@s.whatsapp.net"
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent chat fields")
	func preservesAbsentChatFields() throws {
		var message = Proto_Message()
		message.chat = Proto_Message.Chat()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .chat(ReceivedChatContent(displayName: nil, id: nil)))
	}
}
