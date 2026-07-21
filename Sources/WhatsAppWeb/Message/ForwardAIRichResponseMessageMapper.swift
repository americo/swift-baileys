enum ForwardAIRichResponseMessageMapper {
	static func message(from content: ReceivedAIRichResponseContent) throws -> Proto_Message {
		let response: Proto_AIRichResponseMessage
		if let serializedBytes = content.serializedBytes {
			response = try Proto_AIRichResponseMessage(serializedBytes: serializedBytes)
		} else {
			response = richResponse(from: content)
		}

		var message = Proto_Message()
		message.richResponseMessage = response
		return message
	}

	private static func richResponse(from content: ReceivedAIRichResponseContent) -> Proto_AIRichResponseMessage {
		var response = Proto_AIRichResponseMessage()
		if let messageType = content.messageType {
			response.messageType = protoMessageType(from: messageType)
		}
		response.submessages = content.submessages.map(protoSubMessage)
		if let unifiedResponseData = content.unifiedResponseData {
			var unifiedResponse = Proto_AIRichResponseUnifiedResponse()
			unifiedResponse.data = unifiedResponseData
			response.unifiedResponse = unifiedResponse
		}
		return response
	}

	private static func protoSubMessage(
		from content: ReceivedAIRichResponseSubMessageContent
	) -> Proto_AIRichResponseSubMessage {
		var submessage = Proto_AIRichResponseSubMessage()
		if let type = content.type {
			submessage.messageType = protoSubMessageType(from: type)
		}
		if let text = content.text {
			submessage.messageText = text
		}
		return submessage
	}

	private static func protoMessageType(
		from type: ReceivedAIRichResponseMessageType
	) -> Proto_AIRichResponseMessageType {
		switch type {
		case .unknown:
			.aiRichResponseTypeUnknown
		case .standard:
			.aiRichResponseTypeStandard
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}

	private static func protoSubMessageType(
		from type: ReceivedAIRichResponseSubMessageType
	) -> Proto_AIRichResponseSubMessageType {
		switch type {
		case .unknown:
			.aiRichResponseUnknown
		case .gridImage:
			.aiRichResponseGridImage
		case .text:
			.aiRichResponseText
		case .inlineImage:
			.aiRichResponseInlineImage
		case .table:
			.aiRichResponseTable
		case .code:
			.aiRichResponseCode
		case .dynamic:
			.aiRichResponseDynamic
		case .map:
			.aiRichResponseMap
		case .latex:
			.aiRichResponseLatex
		case .contentItems:
			.aiRichResponseContentItems
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}
}
