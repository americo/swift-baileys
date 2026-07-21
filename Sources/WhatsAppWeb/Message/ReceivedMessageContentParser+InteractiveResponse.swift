extension ReceivedMessageContentParser {
	static func buttonsResponseContent(
		_ response: Proto_Message.ButtonsResponseMessage
	) -> ReceivedButtonsResponseContent {
		let selectedDisplayText: String? = switch response.response {
		case .selectedDisplayText(let text):
			text
		case nil:
			nil
		}

		return ReceivedButtonsResponseContent(
			selectedButtonID: response.hasSelectedButtonID ? response.selectedButtonID : nil,
			selectedDisplayText: selectedDisplayText,
			type: response.hasType ? buttonsResponseType(response.type) : nil
		)
	}

	static func buttonsResponseType(
		_ type: Proto_Message.ButtonsResponseMessage.TypeEnum
	) -> ReceivedButtonsResponseType {
		switch type {
		case .unknown:
			.unknown
		case .displayText:
			.displayText
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	static func listResponseContent(_ response: Proto_Message.ListResponseMessage) -> ReceivedListResponseContent {
		ReceivedListResponseContent(
			title: response.hasTitle ? response.title : nil,
			listType: response.hasListType ? listResponseType(response.listType) : nil,
			selectedRowID: response.hasSingleSelectReply && response.singleSelectReply.hasSelectedRowID
				? response.singleSelectReply.selectedRowID
				: nil,
			description: response.hasDescription_p ? response.description_p : nil
		)
	}

	static func listResponseType(
		_ type: Proto_Message.ListResponseMessage.ListType
	) -> ReceivedListResponseType {
		switch type {
		case .unknown:
			.unknown
		case .singleSelect:
			.singleSelect
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	static func templateButtonReplyContent(
		_ response: Proto_Message.TemplateButtonReplyMessage
	) -> ReceivedTemplateButtonReplyContent {
		ReceivedTemplateButtonReplyContent(
			selectedID: response.hasSelectedID ? response.selectedID : nil,
			selectedDisplayText: response.hasSelectedDisplayText ? response.selectedDisplayText : nil,
			selectedIndex: response.hasSelectedIndex ? response.selectedIndex : nil,
			selectedCarouselCardIndex: response.hasSelectedCarouselCardIndex
				? response.selectedCarouselCardIndex
				: nil
		)
	}

	static func interactiveResponseContent(
		_ response: Proto_Message.InteractiveResponseMessage
	) -> ReceivedInteractiveResponseContent {
		ReceivedInteractiveResponseContent(
			body: response.hasBody ? interactiveResponseBody(response.body) : nil,
			nativeFlowResponse: nativeFlowResponse(response.interactiveResponseMessage)
		)
	}

	static func interactiveResponseBody(
		_ body: Proto_Message.InteractiveResponseMessage.Body
	) -> ReceivedInteractiveResponseBodyContent {
		ReceivedInteractiveResponseBodyContent(
			text: body.hasText ? body.text : nil,
			format: body.hasFormat ? interactiveResponseBodyFormat(body.format) : nil
		)
	}

	static func interactiveResponseBodyFormat(
		_ format: Proto_Message.InteractiveResponseMessage.Body.Format
	) -> ReceivedInteractiveResponseBodyFormat {
		switch format {
		case .default:
			.default
		case .extensions1:
			.extensions1
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	static func nativeFlowResponse(
		_ response: Proto_Message.InteractiveResponseMessage.OneOf_InteractiveResponseMessage?
	) -> ReceivedNativeFlowResponseContent? {
		switch response {
		case .nativeFlowResponseMessage(let nativeFlow):
			ReceivedNativeFlowResponseContent(
				name: nativeFlow.hasName ? nativeFlow.name : nil,
				paramsJSON: nativeFlow.hasParamsJson ? nativeFlow.paramsJson : nil,
				version: nativeFlow.hasVersion ? nativeFlow.version : nil
			)
		case nil:
			nil
		}
	}
}
