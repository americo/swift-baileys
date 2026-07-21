extension MessageContentBuilder {
	static func textWithPresentation(_ content: OutgoingTextContent, quotedRemoteJID: String? = nil) -> Proto_Message {
		var message = textWithLinkPreview(content, quotedRemoteJID: quotedRemoteJID)
		var extendedText = message.extendedTextMessage
		if let backgroundARGB = content.backgroundARGB {
			extendedText.backgroundArgb = backgroundARGB
		}
		if let font = content.font {
			extendedText.font = font.protoFontType
		}
		message.extendedTextMessage = extendedText
		return message
	}
}

private extension OutgoingTextFont {
	var protoFontType: Proto_Message.ExtendedTextMessage.FontType {
		switch self {
		case .system:
			.system
		case .systemText:
			.systemText
		case .fbScript:
			.fbScript
		case .systemBold:
			.systemBold
		case .morningbreezeRegular:
			.morningbreezeRegular
		case .calistogaRegular:
			.calistogaRegular
		case .exo2Extrabold:
			.exo2Extrabold
		case .courierprimeBold:
			.courierprimeBold
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}
}
