enum MessageForwardPassThroughContentBuilder {
	static func message(from source: Proto_Message) -> Proto_Message? {
		if source.hasChat {
			var message = Proto_Message()
			message.chat = source.chat
			return message
		}

		if source.hasScheduledCallCreationMessage {
			var message = Proto_Message()
			message.scheduledCallCreationMessage = source.scheduledCallCreationMessage
			return message
		}

		if source.hasScheduledCallEditMessage {
			var message = Proto_Message()
			message.scheduledCallEditMessage = source.scheduledCallEditMessage
			return message
		}

		if source.hasReactionMessage {
			var message = Proto_Message()
			message.reactionMessage = source.reactionMessage
			return message
		}

		if source.hasEncReactionMessage {
			var message = Proto_Message()
			message.encReactionMessage = source.encReactionMessage
			return message
		}

		if source.hasPollUpdateMessage {
			var message = Proto_Message()
			message.pollUpdateMessage = source.pollUpdateMessage
			return message
		}

		if source.hasPollResultSnapshotMessage {
			var message = Proto_Message()
			message.pollResultSnapshotMessage = source.pollResultSnapshotMessage
			return message
		}

		if source.hasPollResultSnapshotMessageV3 {
			var message = Proto_Message()
			message.pollResultSnapshotMessageV3 = source.pollResultSnapshotMessageV3
			return message
		}

		if source.hasPinInChatMessage {
			var message = Proto_Message()
			message.pinInChatMessage = source.pinInChatMessage
			return message
		}

		if source.hasKeepInChatMessage {
			var message = Proto_Message()
			message.keepInChatMessage = source.keepInChatMessage
			return message
		}

		if source.hasCallLogMesssage {
			var message = Proto_Message()
			message.callLogMesssage = source.callLogMesssage
			return message
		}

		if source.hasMessageHistoryBundle {
			var message = Proto_Message()
			message.messageHistoryBundle = source.messageHistoryBundle
			return message
		}

		if source.hasStickerPackMessage {
			var message = Proto_Message()
			message.stickerPackMessage = source.stickerPackMessage
			return message
		}

		if source.hasRichResponseMessage {
			var message = Proto_Message()
			message.richResponseMessage = source.richResponseMessage
			return message
		}

		if source.hasBcallMessage {
			var message = Proto_Message()
			message.bcallMessage = source.bcallMessage
			return message
		}

		if source.hasStickerSyncRmrMessage {
			var message = Proto_Message()
			message.stickerSyncRmrMessage = source.stickerSyncRmrMessage
			return message
		}

		if source.hasEncCommentMessage {
			var message = Proto_Message()
			message.encCommentMessage = source.encCommentMessage
			return message
		}

		if source.hasEncEventResponseMessage {
			var message = Proto_Message()
			message.encEventResponseMessage = source.encEventResponseMessage
			return message
		}

		if source.hasSecretEncryptedMessage {
			var message = Proto_Message()
			message.secretEncryptedMessage = source.secretEncryptedMessage
			return message
		}

		if source.hasInvoiceMessage {
			var message = Proto_Message()
			message.invoiceMessage = source.invoiceMessage
			return message
		}

		if source.hasPaymentInviteMessage {
			var message = Proto_Message()
			message.paymentInviteMessage = source.paymentInviteMessage
			return message
		}

		if source.hasRequestPaymentMessage {
			var message = Proto_Message()
			message.requestPaymentMessage = source.requestPaymentMessage
			return message
		}

		if source.hasSendPaymentMessage {
			var message = Proto_Message()
			message.sendPaymentMessage = source.sendPaymentMessage
			return message
		}

		if source.hasDeclinePaymentRequestMessage {
			var message = Proto_Message()
			message.declinePaymentRequestMessage = source.declinePaymentRequestMessage
			return message
		}

		if source.hasCancelPaymentRequestMessage {
			var message = Proto_Message()
			message.cancelPaymentRequestMessage = source.cancelPaymentRequestMessage
			return message
		}

		if source.hasMessageHistoryNotice {
			var message = Proto_Message()
			message.messageHistoryNotice = source.messageHistoryNotice
			return message
		}

		if source.hasPlaceholderMessage {
			var message = Proto_Message()
			message.placeholderMessage = source.placeholderMessage
			return message
		}

		if source.hasStatusNotificationMessage {
			var message = Proto_Message()
			message.statusNotificationMessage = source.statusNotificationMessage
			return message
		}

		if source.hasStatusQuestionAnswerMessage {
			var message = Proto_Message()
			message.statusQuestionAnswerMessage = source.statusQuestionAnswerMessage
			return message
		}

		if source.hasQuestionResponseMessage {
			var message = Proto_Message()
			message.questionResponseMessage = source.questionResponseMessage
			return message
		}

		if source.hasStatusQuotedMessage {
			var message = Proto_Message()
			message.statusQuotedMessage = source.statusQuotedMessage
			return message
		}

		if source.hasStatusStickerInteractionMessage {
			var message = Proto_Message()
			message.statusStickerInteractionMessage = source.statusStickerInteractionMessage
			return message
		}

		if source.hasProtocolMessage, source.protocolMessage.type == .sharePhoneNumber {
			var message = Proto_Message()
			message.protocolMessage = source.protocolMessage
			return message
		}

		return nil
	}
}
