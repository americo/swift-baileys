enum ForwardInteractiveResponseMessageMapper {
	static func buttonsResponse(from content: ReceivedButtonsResponseContent) -> Proto_Message {
		var response = Proto_Message.ButtonsResponseMessage()
		if let selectedButtonID = content.selectedButtonID {
			response.selectedButtonID = selectedButtonID
		}
		if let selectedDisplayText = content.selectedDisplayText {
			response.selectedDisplayText = selectedDisplayText
		}
		if let type = content.type {
			response.type = buttonsResponseType(from: type)
		}

		var message = Proto_Message()
		message.buttonsResponseMessage = response
		return message
	}

	static func listResponse(from content: ReceivedListResponseContent) -> Proto_Message {
		var response = Proto_Message.ListResponseMessage()
		if let title = content.title {
			response.title = title
		}
		if let listType = content.listType {
			response.listType = listResponseType(from: listType)
		}
		if let selectedRowID = content.selectedRowID {
			var reply = Proto_Message.ListResponseMessage.SingleSelectReply()
			reply.selectedRowID = selectedRowID
			response.singleSelectReply = reply
		}
		if let description = content.description {
			response.description_p = description
		}

		var message = Proto_Message()
		message.listResponseMessage = response
		return message
	}

	static func templateButtonReply(from content: ReceivedTemplateButtonReplyContent) -> Proto_Message {
		var response = Proto_Message.TemplateButtonReplyMessage()
		if let selectedID = content.selectedID {
			response.selectedID = selectedID
		}
		if let selectedDisplayText = content.selectedDisplayText {
			response.selectedDisplayText = selectedDisplayText
		}
		if let selectedIndex = content.selectedIndex {
			response.selectedIndex = selectedIndex
		}
		if let selectedCarouselCardIndex = content.selectedCarouselCardIndex {
			response.selectedCarouselCardIndex = selectedCarouselCardIndex
		}

		var message = Proto_Message()
		message.templateButtonReplyMessage = response
		return message
	}

	static func interactiveResponse(from content: ReceivedInteractiveResponseContent) -> Proto_Message {
		var response = Proto_Message.InteractiveResponseMessage()
		if let body = content.body {
			response.body = interactiveResponseBody(from: body)
		}
		if let nativeFlowResponse = content.nativeFlowResponse {
			response.nativeFlowResponseMessage = nativeFlowResponseMessage(from: nativeFlowResponse)
		}

		var message = Proto_Message()
		message.interactiveResponseMessage = response
		return message
	}

	private static func buttonsResponseType(
		from type: ReceivedButtonsResponseType
	) -> Proto_Message.ButtonsResponseMessage.TypeEnum {
		switch type {
		case .unknown:
			.unknown
		case .displayText:
			.displayText
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}

	private static func listResponseType(
		from type: ReceivedListResponseType
	) -> Proto_Message.ListResponseMessage.ListType {
		switch type {
		case .unknown:
			.unknown
		case .singleSelect:
			.singleSelect
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}

	private static func interactiveResponseBody(
		from content: ReceivedInteractiveResponseBodyContent
	) -> Proto_Message.InteractiveResponseMessage.Body {
		var body = Proto_Message.InteractiveResponseMessage.Body()
		if let text = content.text {
			body.text = text
		}
		if let format = content.format {
			body.format = switch format {
			case .default:
				.default
			case .extensions1:
				.extensions1
			case .unrecognized(let value):
				.UNRECOGNIZED(value)
			}
		}
		return body
	}

	private static func nativeFlowResponseMessage(
		from content: ReceivedNativeFlowResponseContent
	) -> Proto_Message.InteractiveResponseMessage.NativeFlowResponseMessage {
		var response = Proto_Message.InteractiveResponseMessage.NativeFlowResponseMessage()
		if let name = content.name {
			response.name = name
		}
		if let paramsJSON = content.paramsJSON {
			response.paramsJson = paramsJSON
		}
		if let version = content.version {
			response.version = version
		}
		return response
	}
}
