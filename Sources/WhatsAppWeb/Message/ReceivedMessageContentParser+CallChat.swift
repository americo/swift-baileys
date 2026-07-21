import Foundation

extension ReceivedMessageContentParser {
	static func callContent(_ call: Proto_Message.Call) -> ReceivedCallContent {
		ReceivedCallContent(
			callKey: call.hasCallKey ? call.callKey : nil,
			conversionSource: call.hasConversionSource ? call.conversionSource : nil,
			conversionData: call.hasConversionData ? call.conversionData : nil,
			conversionDelaySeconds: call.hasConversionDelaySeconds ? call.conversionDelaySeconds : nil,
			ctwaSignals: call.hasCtwaSignals ? call.ctwaSignals : nil,
			ctwaPayload: call.hasCtwaPayload ? call.ctwaPayload : nil,
			nativeFlowCallButtonPayload: call.hasNativeFlowCallButtonPayload
				? call.nativeFlowCallButtonPayload
				: nil,
			deeplinkPayload: call.hasDeeplinkPayload ? call.deeplinkPayload : nil
		)
	}

	static func chatContent(_ chat: Proto_Message.Chat) -> ReceivedChatContent {
		ReceivedChatContent(
			displayName: chat.hasDisplayName ? chat.displayName : nil,
			id: chat.hasID ? chat.id : nil
		)
	}
}
