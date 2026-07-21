enum MessageForwardProtocolActionContentBuilder {
	static func message(
		from source: Proto_Message.ProtocolMessageMessage,
		fromMe: Bool,
		forceForward: Bool
	) throws -> Proto_Message {
		guard source.type == .revoke
			  || source.type == .messageEdit
			  || source.type == .ephemeralSetting
			  || source.type == .limitSharing
			  || source.type == .groupMemberLabelChange else {
			throw MessageForwardContentBuilderError.unsupportedContent
		}

		var action = source
		if source.type == .messageEdit, source.hasEditedMessage {
			action.editedMessage = try MessageContentBuilder.forward(
				source.editedMessage,
				fromMe: fromMe,
				forceForward: forceForward
			)
		}
		var message = Proto_Message()
		message.protocolMessage = action
		return message
	}
}
