extension ReceivedMessageContentParser {
	static func statusNotificationContent(
		_ statusNotification: Proto_Message.StatusNotificationMessage
	) -> ReceivedStatusNotificationContent {
		ReceivedStatusNotificationContent(
			responseMessageKey: statusNotification.hasResponseMessageKey
				? messageKey(statusNotification.responseMessageKey)
				: nil,
			originalMessageKey: statusNotification.hasOriginalMessageKey
				? messageKey(statusNotification.originalMessageKey)
				: nil,
			type: statusNotification.hasType ? statusNotificationType(statusNotification.type) : nil
		)
	}

	static func statusQuestionAnswerContent(
		_ answer: Proto_Message.StatusQuestionAnswerMessage
	) -> ReceivedStatusQuestionAnswerContent {
		ReceivedStatusQuestionAnswerContent(
			key: answer.hasKey ? messageKey(answer.key) : nil,
			text: answer.hasText ? answer.text : nil
		)
	}

	static func statusQuotedContent(_ quoted: Proto_Message.StatusQuotedMessage) -> ReceivedStatusQuotedContent {
		ReceivedStatusQuotedContent(
			type: quoted.hasType ? statusQuotedType(quoted.type) : nil,
			text: quoted.hasText ? quoted.text : nil,
			thumbnail: quoted.hasThumbnail ? quoted.thumbnail : nil,
			originalStatusID: quoted.hasOriginalStatusID ? messageKey(quoted.originalStatusID) : nil
		)
	}

	static func statusStickerInteractionContent(
		_ interaction: Proto_Message.StatusStickerInteractionMessage
	) -> ReceivedStatusStickerInteractionContent {
		ReceivedStatusStickerInteractionContent(
			key: interaction.hasKey ? messageKey(interaction.key) : nil,
			stickerKey: interaction.hasStickerKey ? interaction.stickerKey : nil,
			type: interaction.hasType ? statusStickerInteractionType(interaction.type) : nil
		)
	}

	private static func statusNotificationType(
		_ type: Proto_Message.StatusNotificationMessage.StatusNotificationType
	) -> ReceivedStatusNotificationType {
		switch type {
		case .unknown:
			.unknown
		case .statusAddYours:
			.statusAddYours
		case .statusReshare:
			.statusReshare
		case .statusQuestionAnswerReshare:
			.statusQuestionAnswerReshare
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	private static func statusQuotedType(
		_ type: Proto_Message.StatusQuotedMessage.StatusQuotedMessageType
	) -> ReceivedStatusQuotedType {
		switch type {
		case .unknown:
			.unknown
		case .questionAnswer:
			.questionAnswer
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	private static func statusStickerInteractionType(
		_ type: Proto_Message.StatusStickerInteractionMessage.StatusStickerType
	) -> ReceivedStatusStickerInteractionType {
		switch type {
		case .unknown:
			.unknown
		case .reaction:
			.reaction
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}
}
