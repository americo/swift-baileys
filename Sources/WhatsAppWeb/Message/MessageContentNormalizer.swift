enum MessageContentNormalizer {
	static func normalized(_ message: Proto_Message) -> Proto_Message {
		var content = message
		for _ in 0..<5 {
			guard let inner = wrapperContent(of: content) else {
				break
			}

			content = inner
		}

		return content
	}

	static func extractedContent(_ message: Proto_Message) -> Proto_Message {
		let content = normalized(message)
		if content.hasButtonsMessage {
			return extractedContent(from: content.buttonsMessage)
		}

		if content.hasTemplateMessage {
			let template = content.templateMessage
			switch template.format {
			case .hydratedFourRowTemplate(let hydrated):
				return extractedContent(from: hydrated)
			case .fourRowTemplate(let fourRow):
				return extractedContent(from: fourRow)
			default:
				if template.hasHydratedTemplate {
					return extractedContent(from: template.hydratedTemplate)
				}
			}
		}

		return content
	}

	static func futureProofContent(of message: Proto_Message) -> Proto_Message? {
		if message.hasEphemeralMessage, message.ephemeralMessage.hasMessage {
			return message.ephemeralMessage.message
		}

		if message.hasViewOnceMessage, message.viewOnceMessage.hasMessage {
			return message.viewOnceMessage.message
		}

		if message.hasDocumentWithCaptionMessage, message.documentWithCaptionMessage.hasMessage {
			return message.documentWithCaptionMessage.message
		}

		if message.hasViewOnceMessageV2, message.viewOnceMessageV2.hasMessage {
			return message.viewOnceMessageV2.message
		}

		if message.hasViewOnceMessageV2Extension, message.viewOnceMessageV2Extension.hasMessage {
			return message.viewOnceMessageV2Extension.message
		}

		if message.hasLottieStickerMessage, message.lottieStickerMessage.hasMessage {
			return message.lottieStickerMessage.message
		}

		if message.hasPollCreationMessageV4, message.pollCreationMessageV4.hasMessage {
			return message.pollCreationMessageV4.message
		}

		if message.hasGroupMentionedMessage, message.groupMentionedMessage.hasMessage {
			return message.groupMentionedMessage.message
		}

		if message.hasBotInvokeMessage, message.botInvokeMessage.hasMessage {
			return message.botInvokeMessage.message
		}

		if message.hasEditedMessage, message.editedMessage.hasMessage {
			return message.editedMessage.message
		}

		if message.hasAssociatedChildMessage, message.associatedChildMessage.hasMessage {
			return message.associatedChildMessage.message
		}

		if message.hasGroupStatusMessage, message.groupStatusMessage.hasMessage {
			return message.groupStatusMessage.message
		}

		if message.hasGroupStatusMessageV2, message.groupStatusMessageV2.hasMessage {
			return message.groupStatusMessageV2.message
		}

		if message.hasStatusMentionMessage, message.statusMentionMessage.hasMessage {
			return message.statusMentionMessage.message
		}

		if message.hasGroupStatusMentionMessage, message.groupStatusMentionMessage.hasMessage {
			return message.groupStatusMentionMessage.message
		}

		if message.hasEventCoverImage, message.eventCoverImage.hasMessage {
			return message.eventCoverImage.message
		}

		if message.hasPollCreationOptionImageMessage, message.pollCreationOptionImageMessage.hasMessage {
			return message.pollCreationOptionImageMessage.message
		}

		if message.hasStatusAddYours, message.statusAddYours.hasMessage {
			return message.statusAddYours.message
		}

		if message.hasLimitSharingMessage, message.limitSharingMessage.hasMessage {
			return message.limitSharingMessage.message
		}

		if message.hasBotTaskMessage, message.botTaskMessage.hasMessage {
			return message.botTaskMessage.message
		}

		if message.hasQuestionMessage, message.questionMessage.hasMessage {
			return message.questionMessage.message
		}

		if message.hasBotForwardedMessage, message.botForwardedMessage.hasMessage {
			return message.botForwardedMessage.message
		}

		if message.hasQuestionReplyMessage, message.questionReplyMessage.hasMessage {
			return message.questionReplyMessage.message
		}

		return nil
	}

	private static func wrapperContent(of message: Proto_Message) -> Proto_Message? {
		if message.hasDeviceSentMessage, message.deviceSentMessage.hasMessage {
			return message.deviceSentMessage.message
		}

		return futureProofContent(of: message)
	}

	private static func extractedContent(from buttons: Proto_Message.ButtonsMessage) -> Proto_Message {
		switch buttons.header {
		case .imageMessage(let image):
			return message { $0.imageMessage = image }
		case .documentMessage(let document):
			return message { $0.documentMessage = document }
		case .videoMessage(let video):
			return message { $0.videoMessage = video }
		case .locationMessage(let location):
			return message { $0.locationMessage = location }
		default:
			return message { $0.conversation = buttons.hasContentText ? buttons.contentText : "" }
		}
	}

	private static func extractedContent(
		from template: Proto_Message.TemplateMessage.HydratedFourRowTemplate
	) -> Proto_Message {
		switch template.title {
		case .imageMessage(let image):
			return message { $0.imageMessage = image }
		case .documentMessage(let document):
			return message { $0.documentMessage = document }
		case .videoMessage(let video):
			return message { $0.videoMessage = video }
		case .locationMessage(let location):
			return message { $0.locationMessage = location }
		default:
			return message { $0.conversation = template.hasHydratedContentText ? template.hydratedContentText : "" }
		}
	}

	private static func extractedContent(from template: Proto_Message.TemplateMessage.FourRowTemplate) -> Proto_Message {
		switch template.title {
		case .imageMessage(let image):
			return message { $0.imageMessage = image }
		case .documentMessage(let document):
			return message { $0.documentMessage = document }
		case .videoMessage(let video):
			return message { $0.videoMessage = video }
		case .locationMessage(let location):
			return message { $0.locationMessage = location }
		default:
			return message { $0.conversation = "" }
		}
	}

	private static func message(_ assign: (inout Proto_Message) -> Void) -> Proto_Message {
		var message = Proto_Message()
		assign(&message)
		return message
	}
}
