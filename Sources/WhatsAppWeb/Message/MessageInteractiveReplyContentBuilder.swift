import Foundation

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

	static func nativeFlowReply(_ content: OutgoingNativeFlowReplyContent) -> Proto_Message {
		var params: [String: String] = ["id": content.id]
		if content.name == "single_select" {
			params["title"] = content.displayText
			if let description = content.description { params["description"] = description }
		} else {
			params["display_text"] = content.displayText
		}
		let json = (try? JSONSerialization.data(withJSONObject: params, options: [.sortedKeys]))
			.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

		var body = Proto_Message.InteractiveResponseMessage.Body()
		body.text = content.displayText
		body.format = .extensions1

		var flow = Proto_Message.InteractiveResponseMessage.NativeFlowResponseMessage()
		flow.name = content.name
		flow.paramsJson = json
		flow.version = 3

		var response = Proto_Message.InteractiveResponseMessage()
		response.body = body
		response.nativeFlowResponseMessage = flow

		var message = Proto_Message()
		message.interactiveResponseMessage = response
		return message
	}
}
