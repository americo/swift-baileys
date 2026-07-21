enum ForwardCallChatMessageMapper {
	static func call(from content: ReceivedCallContent) -> Proto_Message {
		var callMessage = Proto_Message.Call()
		if let callKey = content.callKey {
			callMessage.callKey = callKey
		}
		if let conversionSource = content.conversionSource {
			callMessage.conversionSource = conversionSource
		}
		if let conversionData = content.conversionData {
			callMessage.conversionData = conversionData
		}
		if let conversionDelaySeconds = content.conversionDelaySeconds {
			callMessage.conversionDelaySeconds = conversionDelaySeconds
		}
		if let ctwaSignals = content.ctwaSignals {
			callMessage.ctwaSignals = ctwaSignals
		}
		if let ctwaPayload = content.ctwaPayload {
			callMessage.ctwaPayload = ctwaPayload
		}
		if let nativeFlowCallButtonPayload = content.nativeFlowCallButtonPayload {
			callMessage.nativeFlowCallButtonPayload = nativeFlowCallButtonPayload
		}
		if let deeplinkPayload = content.deeplinkPayload {
			callMessage.deeplinkPayload = deeplinkPayload
		}

		var message = Proto_Message()
		message.call = callMessage
		return message
	}

	static func chat(from content: ReceivedChatContent) -> Proto_Message {
		var chatMessage = Proto_Message.Chat()
		if let displayName = content.displayName {
			chatMessage.displayName = displayName
		}
		if let id = content.id {
			chatMessage.id = id
		}

		var message = Proto_Message()
		message.chat = chatMessage
		return message
	}
}
