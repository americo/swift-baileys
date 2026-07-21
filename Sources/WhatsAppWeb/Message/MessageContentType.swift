enum MessageContentType: String, Equatable, Sendable {
	case conversation
	case imageMessage
	case contactMessage
	case locationMessage
	case extendedTextMessage
	case documentMessage
	case audioMessage
	case videoMessage
	case protocolMessage
	case contactsArrayMessage
	case highlyStructuredMessage
	case fastRatchetKeySenderKeyDistributionMessage
	case sendPaymentMessage
	case liveLocationMessage
	case requestPaymentMessage
	case declinePaymentRequestMessage
	case cancelPaymentRequestMessage
	case templateMessage
	case stickerMessage
	case groupInviteMessage
	case templateButtonReplyMessage
	case productMessage
	case deviceSentMessage
	case listMessage
	case viewOnceMessage
	case orderMessage
	case listResponseMessage
	case ephemeralMessage
	case invoiceMessage
	case buttonsMessage
	case buttonsResponseMessage
	case paymentInviteMessage
	case interactiveMessage
	case reactionMessage
	case stickerSyncRmrMessage
	case interactiveResponseMessage
	case pollCreationMessage
	case pollUpdateMessage
	case keepInChatMessage
	case documentWithCaptionMessage
	case requestPhoneNumberMessage
	case viewOnceMessageV2
	case encReactionMessage
	case editedMessage
	case viewOnceMessageV2Extension
	case pollCreationMessageV2
	case scheduledCallCreationMessage
	case groupMentionedMessage
	case pinInChatMessage
	case pollCreationMessageV3
	case scheduledCallEditMessage
	case ptvMessage
	case botInvokeMessage
	case callLogMesssage
	case messageHistoryBundle
	case encCommentMessage
	case bcallMessage
	case lottieStickerMessage
	case eventMessage
	case encEventResponseMessage
	case commentMessage
	case newsletterAdminInviteMessage
	case placeholderMessage
	case secretEncryptedMessage
	case albumMessage
	case eventCoverImage
	case stickerPackMessage
	case statusMentionMessage
	case pollResultSnapshotMessage
	case pollCreationOptionImageMessage
	case associatedChildMessage
	case groupStatusMentionMessage
	case pollCreationMessageV4
	case statusAddYours
	case groupStatusMessage
	case richResponseMessage
	case statusNotificationMessage
	case limitSharingMessage
	case botTaskMessage
	case questionMessage
	case messageHistoryNotice
	case groupStatusMessageV2
	case botForwardedMessage
	case statusQuestionAnswerMessage
	case questionReplyMessage
	case questionResponseMessage
	case statusQuotedMessage
	case statusStickerInteractionMessage
	case pollCreationMessageV5
	case newsletterFollowerInviteMessageV2
	case pollResultSnapshotMessageV3
}

enum MessageContentTypeResolver {
	static func normalizedContentType(of message: Proto_Message) -> MessageContentType? {
		contentType(of: MessageContentNormalizer.normalized(message))
	}

	static func contentType(of message: Proto_Message) -> MessageContentType? {
		if message.hasConversation {
			return .conversation
		}

		if message.hasImageMessage {
			return .imageMessage
		}

		if message.hasContactMessage {
			return .contactMessage
		}

		if message.hasLocationMessage {
			return .locationMessage
		}

		if message.hasExtendedTextMessage {
			return .extendedTextMessage
		}

		if message.hasDocumentMessage {
			return .documentMessage
		}

		if message.hasAudioMessage {
			return .audioMessage
		}

		if message.hasVideoMessage {
			return .videoMessage
		}

		if message.hasProtocolMessage {
			return .protocolMessage
		}

		if message.hasContactsArrayMessage {
			return .contactsArrayMessage
		}

		if message.hasHighlyStructuredMessage {
			return .highlyStructuredMessage
		}

		if message.hasFastRatchetKeySenderKeyDistributionMessage {
			return .fastRatchetKeySenderKeyDistributionMessage
		}

		if message.hasSendPaymentMessage {
			return .sendPaymentMessage
		}

		if message.hasLiveLocationMessage {
			return .liveLocationMessage
		}

		if message.hasRequestPaymentMessage {
			return .requestPaymentMessage
		}

		if message.hasDeclinePaymentRequestMessage {
			return .declinePaymentRequestMessage
		}

		if message.hasCancelPaymentRequestMessage {
			return .cancelPaymentRequestMessage
		}

		if message.hasTemplateMessage {
			return .templateMessage
		}

		if message.hasStickerMessage {
			return .stickerMessage
		}

		if message.hasGroupInviteMessage {
			return .groupInviteMessage
		}

		if message.hasTemplateButtonReplyMessage {
			return .templateButtonReplyMessage
		}

		if message.hasProductMessage {
			return .productMessage
		}

		if message.hasDeviceSentMessage {
			return .deviceSentMessage
		}

		if message.hasListMessage {
			return .listMessage
		}

		if message.hasViewOnceMessage {
			return .viewOnceMessage
		}

		if message.hasOrderMessage {
			return .orderMessage
		}

		if message.hasListResponseMessage {
			return .listResponseMessage
		}

		if message.hasEphemeralMessage {
			return .ephemeralMessage
		}

		return laterContentType(of: message)
	}

	private static func laterContentType(of message: Proto_Message) -> MessageContentType? {
		if message.hasInvoiceMessage {
			return .invoiceMessage
		}

		if message.hasButtonsMessage {
			return .buttonsMessage
		}

		if message.hasButtonsResponseMessage {
			return .buttonsResponseMessage
		}

		if message.hasPaymentInviteMessage {
			return .paymentInviteMessage
		}

		if message.hasInteractiveMessage {
			return .interactiveMessage
		}

		if message.hasReactionMessage {
			return .reactionMessage
		}

		if message.hasStickerSyncRmrMessage {
			return .stickerSyncRmrMessage
		}

		if message.hasInteractiveResponseMessage {
			return .interactiveResponseMessage
		}

		if message.hasPollCreationMessage {
			return .pollCreationMessage
		}

		if message.hasPollUpdateMessage {
			return .pollUpdateMessage
		}

		if message.hasKeepInChatMessage {
			return .keepInChatMessage
		}

		if message.hasDocumentWithCaptionMessage {
			return .documentWithCaptionMessage
		}

		if message.hasRequestPhoneNumberMessage {
			return .requestPhoneNumberMessage
		}

		if message.hasViewOnceMessageV2 {
			return .viewOnceMessageV2
		}

		if message.hasEncReactionMessage {
			return .encReactionMessage
		}

		if message.hasEditedMessage {
			return .editedMessage
		}

		if message.hasViewOnceMessageV2Extension {
			return .viewOnceMessageV2Extension
		}

		if message.hasPollCreationMessageV2 {
			return .pollCreationMessageV2
		}

		if message.hasScheduledCallCreationMessage {
			return .scheduledCallCreationMessage
		}

		if message.hasGroupMentionedMessage {
			return .groupMentionedMessage
		}

		if message.hasPinInChatMessage {
			return .pinInChatMessage
		}

		if message.hasPollCreationMessageV3 {
			return .pollCreationMessageV3
		}

		if message.hasScheduledCallEditMessage {
			return .scheduledCallEditMessage
		}

		if message.hasPtvMessage {
			return .ptvMessage
		}

		if message.hasBotInvokeMessage {
			return .botInvokeMessage
		}

		if message.hasCallLogMesssage {
			return .callLogMesssage
		}

		if message.hasMessageHistoryBundle {
			return .messageHistoryBundle
		}

		return latestContentType(of: message)
	}

	private static func latestContentType(of message: Proto_Message) -> MessageContentType? {
		if message.hasEncCommentMessage {
			return .encCommentMessage
		}

		if message.hasBcallMessage {
			return .bcallMessage
		}

		if message.hasLottieStickerMessage {
			return .lottieStickerMessage
		}

		if message.hasEventMessage {
			return .eventMessage
		}

		if message.hasEncEventResponseMessage {
			return .encEventResponseMessage
		}

		if message.hasCommentMessage {
			return .commentMessage
		}

		if message.hasNewsletterAdminInviteMessage {
			return .newsletterAdminInviteMessage
		}

		if message.hasPlaceholderMessage {
			return .placeholderMessage
		}

		if message.hasSecretEncryptedMessage {
			return .secretEncryptedMessage
		}

		if message.hasAlbumMessage {
			return .albumMessage
		}

		if message.hasEventCoverImage {
			return .eventCoverImage
		}

		if message.hasStickerPackMessage {
			return .stickerPackMessage
		}

		if message.hasStatusMentionMessage {
			return .statusMentionMessage
		}

		if message.hasPollResultSnapshotMessage {
			return .pollResultSnapshotMessage
		}

		if message.hasPollCreationOptionImageMessage {
			return .pollCreationOptionImageMessage
		}

		if message.hasAssociatedChildMessage {
			return .associatedChildMessage
		}

		if message.hasGroupStatusMentionMessage {
			return .groupStatusMentionMessage
		}

		if message.hasPollCreationMessageV4 {
			return .pollCreationMessageV4
		}

		if message.hasStatusAddYours {
			return .statusAddYours
		}

		if message.hasGroupStatusMessage {
			return .groupStatusMessage
		}

		return newestContentType(of: message)
	}

	private static func newestContentType(of message: Proto_Message) -> MessageContentType? {
		if message.hasRichResponseMessage {
			return .richResponseMessage
		}

		if message.hasStatusNotificationMessage {
			return .statusNotificationMessage
		}

		if message.hasLimitSharingMessage {
			return .limitSharingMessage
		}

		if message.hasBotTaskMessage {
			return .botTaskMessage
		}

		if message.hasQuestionMessage {
			return .questionMessage
		}

		if message.hasMessageHistoryNotice {
			return .messageHistoryNotice
		}

		if message.hasGroupStatusMessageV2 {
			return .groupStatusMessageV2
		}

		if message.hasBotForwardedMessage {
			return .botForwardedMessage
		}

		if message.hasStatusQuestionAnswerMessage {
			return .statusQuestionAnswerMessage
		}

		if message.hasQuestionReplyMessage {
			return .questionReplyMessage
		}

		if message.hasQuestionResponseMessage {
			return .questionResponseMessage
		}

		if message.hasStatusQuotedMessage {
			return .statusQuotedMessage
		}

		if message.hasStatusStickerInteractionMessage {
			return .statusStickerInteractionMessage
		}

		if message.hasPollCreationMessageV5 {
			return .pollCreationMessageV5
		}

		if message.hasNewsletterFollowerInviteMessageV2 {
			return .newsletterFollowerInviteMessageV2
		}

		if message.hasPollResultSnapshotMessageV3 {
			return .pollResultSnapshotMessageV3
		}

		return nil
	}
}
