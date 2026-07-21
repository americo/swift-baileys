enum ForwardButtonsMessageMapper {
	static func message(from content: ReceivedButtonsContent) -> Proto_Message {
		var buttons = Proto_Message.ButtonsMessage()
		if let contentText = content.contentText {
			buttons.contentText = contentText
		}
		if let footerText = content.footerText {
			buttons.footerText = footerText
		}
		buttons.buttons = content.buttons.map(protoButton)
		if let headerType = content.headerType {
			buttons.headerType = protoHeaderType(from: headerType)
		}
		if let header = content.header {
			switch header {
			case .text(let text):
				buttons.text = text
			case .document(let document):
				buttons.documentMessage = ForwardMediaMessageMapper.document(from: document)
			case .image(let image):
				buttons.imageMessage = ForwardMediaMessageMapper.image(from: image)
			case .video(let video):
				buttons.videoMessage = ForwardMediaMessageMapper.video(from: video)
			case .location(let location):
				buttons.locationMessage = ForwardMediaMessageMapper.location(from: location)
			}
		}

		var message = Proto_Message()
		message.buttonsMessage = buttons
		return message
	}

	private static func protoButton(
		from content: ReceivedButtonContent
	) -> Proto_Message.ButtonsMessage.Button {
		var button = Proto_Message.ButtonsMessage.Button()
		if let buttonID = content.buttonID {
			button.buttonID = buttonID
		}
		if let displayText = content.displayText {
			var text = Proto_Message.ButtonsMessage.Button.ButtonText()
			text.displayText = displayText
			button.buttonText = text
		}
		if let type = content.type {
			button.type = protoButtonType(from: type)
		}
		if let nativeFlowInfo = content.nativeFlowInfo {
			button.nativeFlowInfo = protoNativeFlowInfo(from: nativeFlowInfo)
		}
		return button
	}

	private static func protoNativeFlowInfo(
		from content: ReceivedButtonNativeFlowInfoContent
	) -> Proto_Message.ButtonsMessage.Button.NativeFlowInfo {
		var info = Proto_Message.ButtonsMessage.Button.NativeFlowInfo()
		if let name = content.name {
			info.name = name
		}
		if let paramsJSON = content.paramsJSON {
			info.paramsJson = paramsJSON
		}
		return info
	}

	private static func protoButtonType(
		from type: ReceivedButtonType
	) -> Proto_Message.ButtonsMessage.Button.TypeEnum {
		switch type {
		case .unknown:
			.unknown
		case .response:
			.response
		case .nativeFlow:
			.nativeFlow
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}

	private static func protoHeaderType(
		from type: ReceivedButtonsHeaderType
	) -> Proto_Message.ButtonsMessage.HeaderType {
		switch type {
		case .unknown:
			.unknown
		case .empty:
			.empty
		case .text:
			.text
		case .document:
			.document
		case .image:
			.image
		case .video:
			.video
		case .location:
			.location
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}
}
