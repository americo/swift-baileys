extension MessageContentBuilder {
	static func buttonReply(_ content: OutgoingButtonReplyContent) -> Proto_Message {
		switch content.style {
		case .plain:
			var response = Proto_Message.ButtonsResponseMessage()
			response.selectedButtonID = content.id
			response.selectedDisplayText = content.displayText
			response.type = .displayText

			var message = Proto_Message()
			message.buttonsResponseMessage = response
			return message
		case .template:
			var response = Proto_Message.TemplateButtonReplyMessage()
			response.selectedID = content.id
			response.selectedDisplayText = content.displayText
			response.selectedIndex = content.index

			var message = Proto_Message()
			message.templateButtonReplyMessage = response
			return message
		}
	}

	static func listReply(_ content: OutgoingListReplyContent) -> Proto_Message {
		var reply = Proto_Message.ListResponseMessage.SingleSelectReply()
		reply.selectedRowID = content.selectedRowID

		var response = Proto_Message.ListResponseMessage()
		response.title = content.title
		response.listType = .singleSelect
		response.singleSelectReply = reply
		if let description = content.description {
			response.description_p = description
		}

		var message = Proto_Message()
		message.listResponseMessage = response
		return message
	}
}
