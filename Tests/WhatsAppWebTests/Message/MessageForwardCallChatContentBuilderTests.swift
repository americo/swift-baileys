import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Message forward call and chat content builder")
struct MessageForwardCallChatContentBuilderTests {
	@Test("forwards call messages with forwarding context")
	func forwardsCallMessagesWithForwardingContext() throws {
		var call = Proto_Message.Call()
		call.callKey = Data([0x01, 0x02])
		call.conversionSource = "ad"
		call.conversionData = Data([0x03])
		call.conversionDelaySeconds = 7
		call.ctwaSignals = "signals"
		call.ctwaPayload = Data([0x04])
		call.nativeFlowCallButtonPayload = "native-flow"
		call.deeplinkPayload = "deeplink"
		var source = Proto_Message()
		source.call = call

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasCall)
		#expect(message.call.callKey == Data([0x01, 0x02]))
		#expect(message.call.conversionSource == "ad")
		#expect(message.call.conversionData == Data([0x03]))
		#expect(message.call.conversionDelaySeconds == 7)
		#expect(message.call.ctwaSignals == "signals")
		#expect(message.call.ctwaPayload == Data([0x04]))
		#expect(message.call.nativeFlowCallButtonPayload == "native-flow")
		#expect(message.call.deeplinkPayload == "deeplink")
		#expect(message.call.contextInfo.isForwarded)
		#expect(message.call.contextInfo.forwardingScore == 1)
	}

	@Test("forwards chat and business call messages as pass-through content")
	func forwardsChatAndBusinessCallMessagesAsPassThroughContent() throws {
		var chat = Proto_Message.Chat()
		chat.displayName = "Support"
		chat.id = "support-chat"
		var chatSource = Proto_Message()
		chatSource.chat = chat

		let chatMessage = try MessageContentBuilder.forward(chatSource, fromMe: false)

		#expect(chatMessage.hasChat)
		#expect(chatMessage.chat.displayName == "Support")
		#expect(chatMessage.chat.id == "support-chat")

		var businessCall = Proto_Message.BCallMessage()
		businessCall.sessionID = "session-1"
		businessCall.mediaType = .video
		businessCall.masterKey = Data([0x05, 0x06])
		businessCall.caption = "Call us"
		var businessCallSource = Proto_Message()
		businessCallSource.bcallMessage = businessCall

		let businessCallMessage = try MessageContentBuilder.forward(businessCallSource, fromMe: false)

		#expect(businessCallMessage.hasBcallMessage)
		#expect(businessCallMessage.bcallMessage.sessionID == "session-1")
		#expect(businessCallMessage.bcallMessage.mediaType == .video)
		#expect(businessCallMessage.bcallMessage.masterKey == Data([0x05, 0x06]))
		#expect(businessCallMessage.bcallMessage.caption == "Call us")
	}
}
