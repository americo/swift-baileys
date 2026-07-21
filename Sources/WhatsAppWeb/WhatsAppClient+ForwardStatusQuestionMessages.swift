enum ForwardStatusQuestionMessageMapper {
	static func statusNotification(from content: ReceivedStatusNotificationContent) -> Proto_Message {
		var status = Proto_Message.StatusNotificationMessage()
		if let key = content.responseMessageKey {
			status.responseMessageKey = ForwardMessageKeyMapper.key(from: key)
		}
		if let key = content.originalMessageKey {
			status.originalMessageKey = ForwardMessageKeyMapper.key(from: key)
		}
		if let type = content.type {
			status.type = statusNotificationType(from: type)
		}

		var message = Proto_Message()
		message.statusNotificationMessage = status
		return message
	}

	static func statusQuestionAnswer(from content: ReceivedStatusQuestionAnswerContent) -> Proto_Message {
		var answer = Proto_Message.StatusQuestionAnswerMessage()
		if let key = content.key {
			answer.key = ForwardMessageKeyMapper.key(from: key)
		}
		if let text = content.text {
			answer.text = text
		}

		var message = Proto_Message()
		message.statusQuestionAnswerMessage = answer
		return message
	}

	static func questionResponse(from content: ReceivedQuestionResponseContent) -> Proto_Message {
		var response = Proto_Message.QuestionResponseMessage()
		if let key = content.key {
			response.key = ForwardMessageKeyMapper.key(from: key)
		}
		if let text = content.text {
			response.text = text
		}

		var message = Proto_Message()
		message.questionResponseMessage = response
		return message
	}

	static func statusQuoted(from content: ReceivedStatusQuotedContent) -> Proto_Message {
		var quoted = Proto_Message.StatusQuotedMessage()
		if let type = content.type {
			quoted.type = statusQuotedType(from: type)
		}
		if let text = content.text {
			quoted.text = text
		}
		if let thumbnail = content.thumbnail {
			quoted.thumbnail = thumbnail
		}
		if let originalStatusID = content.originalStatusID {
			quoted.originalStatusID = ForwardMessageKeyMapper.key(from: originalStatusID)
		}

		var message = Proto_Message()
		message.statusQuotedMessage = quoted
		return message
	}

	static func statusStickerInteraction(from content: ReceivedStatusStickerInteractionContent) -> Proto_Message {
		var interaction = Proto_Message.StatusStickerInteractionMessage()
		if let key = content.key {
			interaction.key = ForwardMessageKeyMapper.key(from: key)
		}
		if let stickerKey = content.stickerKey {
			interaction.stickerKey = stickerKey
		}
		if let type = content.type {
			interaction.type = statusStickerInteractionType(from: type)
		}

		var message = Proto_Message()
		message.statusStickerInteractionMessage = interaction
		return message
	}

	private static func statusNotificationType(
		from type: ReceivedStatusNotificationType
	) -> Proto_Message.StatusNotificationMessage.StatusNotificationType {
		switch type {
		case .unknown:
			.unknown
		case .statusAddYours:
			.statusAddYours
		case .statusReshare:
			.statusReshare
		case .statusQuestionAnswerReshare:
			.statusQuestionAnswerReshare
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}

	private static func statusQuotedType(
		from type: ReceivedStatusQuotedType
	) -> Proto_Message.StatusQuotedMessage.StatusQuotedMessageType {
		switch type {
		case .unknown:
			.unknown
		case .questionAnswer:
			.questionAnswer
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}

	private static func statusStickerInteractionType(
		from type: ReceivedStatusStickerInteractionType
	) -> Proto_Message.StatusStickerInteractionMessage.StatusStickerType {
		switch type {
		case .unknown:
			.unknown
		case .reaction:
			.reaction
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}
}
