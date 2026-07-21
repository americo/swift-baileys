extension ReceivedMessageContentParser {
	static func buttonsContent(_ buttons: Proto_Message.ButtonsMessage) -> ReceivedButtonsContent {
		ReceivedButtonsContent(
			contentText: buttons.hasContentText ? buttons.contentText : nil,
			footerText: buttons.hasFooterText ? buttons.footerText : nil,
			buttons: buttons.buttons.map(buttonContent),
			headerType: buttons.hasHeaderType ? buttonsHeaderType(buttons.headerType) : nil,
			header: buttonsHeader(buttons.header)
		)
	}

	static func buttonContent(_ button: Proto_Message.ButtonsMessage.Button) -> ReceivedButtonContent {
		ReceivedButtonContent(
			buttonID: button.hasButtonID ? button.buttonID : nil,
			displayText: button.hasButtonText && button.buttonText.hasDisplayText ? button.buttonText.displayText : nil,
			type: button.hasType ? buttonType(button.type) : nil,
			nativeFlowInfo: button.hasNativeFlowInfo ? buttonNativeFlowInfo(button.nativeFlowInfo) : nil
		)
	}

	static func buttonNativeFlowInfo(
		_ info: Proto_Message.ButtonsMessage.Button.NativeFlowInfo
	) -> ReceivedButtonNativeFlowInfoContent {
		ReceivedButtonNativeFlowInfoContent(
			name: info.hasName ? info.name : nil,
			paramsJSON: info.hasParamsJson ? info.paramsJson : nil
		)
	}

	static func buttonsHeaderType(
		_ type: Proto_Message.ButtonsMessage.HeaderType
	) -> ReceivedButtonsHeaderType {
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
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	static func buttonType(_ type: Proto_Message.ButtonsMessage.Button.TypeEnum) -> ReceivedButtonType {
		switch type {
		case .unknown:
			.unknown
		case .response:
			.response
		case .nativeFlow:
			.nativeFlow
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	static func buttonsHeader(
		_ header: Proto_Message.ButtonsMessage.OneOf_Header?
	) -> ReceivedButtonsHeaderContent? {
		switch header {
		case .text(let text):
			.text(text)
		case .documentMessage(let document):
			.document(documentContent(document))
		case .imageMessage(let image):
			.image(imageContent(image))
		case .videoMessage(let video):
			.video(videoContent(video))
		case .locationMessage(let location):
			.location(locationContent(location))
		case nil:
			nil
		}
	}
}
