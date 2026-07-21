enum ReceivedMessageContentParser {
	static func parse(_ message: Proto_Message) -> ReceivedMessageContent? {
		let message = MessageContentNormalizer.normalized(message)

		if message.hasConversation {
			return .text(message.conversation)
		}

		if message.hasExtendedTextMessage {
			return textContent(message.extendedTextMessage)
		}

		if message.hasImageMessage {
			return .image(imageContent(message.imageMessage))
		}

		if message.hasDocumentMessage {
			return .document(documentContent(message.documentMessage))
		}

		if message.hasAudioMessage {
			return .audio(audioContent(message.audioMessage))
		}

		if message.hasVideoMessage {
			return .video(videoContent(message.videoMessage))
		}

		if message.hasCall {
			return .call(callContent(message.call))
		}

		if message.hasChat {
			return .chat(chatContent(message.chat))
		}

		if message.hasPtvMessage {
			return .video(videoContent(message.ptvMessage))
		}

		if message.hasStickerMessage {
			return .sticker(stickerContent(message.stickerMessage))
		}

		if message.hasLocationMessage {
			return .location(locationContent(message.locationMessage))
		}

		if message.hasLiveLocationMessage {
			let liveLocation = message.liveLocationMessage
			return .liveLocation(ReceivedLiveLocationContent(
				latitude: liveLocation.degreesLatitude,
				longitude: liveLocation.degreesLongitude,
				accuracyInMeters: liveLocation.hasAccuracyInMeters ? liveLocation.accuracyInMeters : nil,
				speedInMetersPerSecond: liveLocation.hasSpeedInMps ? liveLocation.speedInMps : nil,
				degreesClockwiseFromMagneticNorth: liveLocation.hasDegreesClockwiseFromMagneticNorth
					? liveLocation.degreesClockwiseFromMagneticNorth
					: nil,
				caption: liveLocation.hasCaption ? liveLocation.caption : nil,
				sequenceNumber: liveLocation.hasSequenceNumber ? liveLocation.sequenceNumber : nil,
				timeOffsetSeconds: liveLocation.hasTimeOffset ? liveLocation.timeOffset : nil,
				jpegThumbnail: liveLocation.hasJpegThumbnail ? liveLocation.jpegThumbnail : nil
			))
		}

		if message.hasEventMessage {
			let event = message.eventMessage
			return .event(ReceivedEventContent(
				name: event.hasName ? event.name : nil,
				description: event.hasDescription_p ? event.description_p : nil,
				startTime: event.hasStartTime ? event.startTime : nil,
				endTime: event.hasEndTime ? event.endTime : nil,
				joinLink: event.hasJoinLink ? event.joinLink : nil,
				isCanceled: event.hasIsCanceled ? event.isCanceled : nil,
				extraGuestsAllowed: event.hasExtraGuestsAllowed ? event.extraGuestsAllowed : nil,
				isScheduledCall: event.hasIsScheduleCall ? event.isScheduleCall : nil,
				location: event.hasLocation ? locationContent(event.location) : nil
			))
		}

		if message.hasEncEventResponseMessage {
			let response = message.encEventResponseMessage
			return .encryptedEventResponse(ReceivedEncryptedEventResponseContent(
				eventCreationMessageKey: response.hasEventCreationMessageKey
					? messageKey(response.eventCreationMessageKey)
					: nil,
				encryptedPayload: response.hasEncPayload ? response.encPayload : nil,
				encryptedIV: response.hasEncIv ? response.encIv : nil
			))
		}

		if message.hasScheduledCallCreationMessage {
			let scheduledCall = message.scheduledCallCreationMessage
			let callType: ReceivedScheduledCallType = switch scheduledCall.callType {
			case .unknown:
				.unknown
			case .voice:
				.voice
			case .video:
				.video
			case .UNRECOGNIZED(let value):
				.unrecognized(value)
			}
			return .scheduledCallCreation(ReceivedScheduledCallCreationContent(
				scheduledTimestampMilliseconds: scheduledCall.hasScheduledTimestampMs
					? scheduledCall.scheduledTimestampMs
					: nil,
				callType: callType,
				title: scheduledCall.hasTitle ? scheduledCall.title : nil
			))
		}

		if message.hasScheduledCallEditMessage {
			let scheduledCall = message.scheduledCallEditMessage
			let editType: ReceivedScheduledCallEditType = switch scheduledCall.editType {
			case .unknown:
				.unknown
			case .cancel:
				.cancel
			case .UNRECOGNIZED(let value):
				.unrecognized(value)
			}
			return .scheduledCallEdit(ReceivedScheduledCallEditContent(
				key: scheduledCall.hasKey ? messageKey(scheduledCall.key) : nil,
				editType: editType
			))
		}

		if message.hasContactMessage {
			let contact = message.contactMessage
			return .contact(ReceivedContactContent(
				displayName: contact.displayName,
				vcard: contact.vcard
			))
		}

		if message.hasContactsArrayMessage {
			let contacts = message.contactsArrayMessage
			return .contacts(ReceivedContactsContent(
				displayName: contacts.hasDisplayName ? contacts.displayName : nil,
				contacts: contacts.contacts.map {
					ReceivedContactContent(displayName: $0.displayName, vcard: $0.vcard)
				}
			))
		}

		if message.hasRequestPhoneNumberMessage {
			return .requestPhoneNumber(ReceivedRequestPhoneNumberContent())
		}

		if message.hasTemplateMessage {
			let extracted = MessageContentNormalizer.extractedContent(message)
			if !extracted.hasTemplateMessage {
				return parse(extracted)
			}
		}

		if message.hasHighlyStructuredMessage {
			return .highlyStructured(highlyStructuredContent(message.highlyStructuredMessage))
		}

		if message.hasAlbumMessage {
			let album = message.albumMessage
			return .album(ReceivedAlbumContent(
				expectedImageCount: album.hasExpectedImageCount ? album.expectedImageCount : nil,
				expectedVideoCount: album.hasExpectedVideoCount ? album.expectedVideoCount : nil
			))
		}

		if message.hasOrderMessage {
			return .order(orderContent(message.orderMessage))
		}

		if message.hasProductMessage {
			return .product(productContent(message.productMessage))
		}

		if message.hasListMessage {
			return .list(listContent(message.listMessage))
		}

		if message.hasButtonsMessage {
			return .buttons(buttonsContent(message.buttonsMessage))
		}

		if message.hasInteractiveMessage {
			return .interactive(interactiveContent(message.interactiveMessage))
		}

		if message.hasButtonsResponseMessage {
			return .buttonsResponse(buttonsResponseContent(message.buttonsResponseMessage))
		}

		if message.hasListResponseMessage {
			return .listResponse(listResponseContent(message.listResponseMessage))
		}

		if message.hasTemplateButtonReplyMessage {
			return .templateButtonReply(templateButtonReplyContent(message.templateButtonReplyMessage))
		}

		if message.hasInteractiveResponseMessage {
			return .interactiveResponse(interactiveResponseContent(message.interactiveResponseMessage))
		}

		if message.hasGroupInviteMessage {
			let invite = message.groupInviteMessage
			let groupType: ReceivedGroupInviteType = switch invite.groupType {
			case .default:
				.default
			case .parent:
				.parent
			case .UNRECOGNIZED(let value):
				.unrecognized(value)
			}
			return .groupInvite(ReceivedGroupInviteContent(
				groupJID: invite.hasGroupJid ? invite.groupJid : nil,
				inviteCode: invite.hasInviteCode ? invite.inviteCode : nil,
				inviteExpiration: invite.hasInviteExpiration ? invite.inviteExpiration : nil,
				groupName: invite.hasGroupName ? invite.groupName : nil,
				caption: invite.hasCaption ? invite.caption : nil,
				groupType: groupType,
				jpegThumbnail: invite.hasJpegThumbnail ? invite.jpegThumbnail : nil
			))
		}

		if message.hasPollCreationMessage {
			return .pollCreation(pollCreationContent(message.pollCreationMessage))
		}

		if message.hasPollCreationMessageV2 {
			return .pollCreation(pollCreationContent(message.pollCreationMessageV2))
		}

		if message.hasPollCreationMessageV3 {
			return .pollCreation(pollCreationContent(message.pollCreationMessageV3))
		}

		if message.hasPollCreationMessageV5 {
			return .pollCreation(pollCreationContent(message.pollCreationMessageV5))
		}

		if message.hasPollUpdateMessage {
			let update = message.pollUpdateMessage
			return .pollUpdate(ReceivedPollUpdateContent(
				pollCreationMessageKey: update.hasPollCreationMessageKey ? messageKey(update.pollCreationMessageKey) : nil,
				encryptedPayload: update.hasVote && update.vote.hasEncPayload ? update.vote.encPayload : nil,
				encryptedIV: update.hasVote && update.vote.hasEncIv ? update.vote.encIv : nil,
				senderTimestampMilliseconds: update.hasSenderTimestampMs ? update.senderTimestampMs : nil
			))
		}

		if message.hasPollResultSnapshotMessage {
			return .pollResultSnapshot(pollResultSnapshotContent(message.pollResultSnapshotMessage))
		}

		if message.hasPollResultSnapshotMessageV3 {
			return .pollResultSnapshot(pollResultSnapshotContent(message.pollResultSnapshotMessageV3))
		}

		if message.hasProtocolMessage {
			return protocolContent(message.protocolMessage)
		}

		if message.hasReactionMessage {
			let reaction = message.reactionMessage
			return .reaction(ReceivedReactionContent(
				key: reaction.hasKey ? messageKey(reaction.key) : nil,
				text: reaction.hasText ? reaction.text : nil,
				groupingKey: reaction.hasGroupingKey ? reaction.groupingKey : nil,
				senderTimestampMilliseconds: reaction.hasSenderTimestampMs ? reaction.senderTimestampMs : nil
			))
		}

		if message.hasEncReactionMessage {
			return .encryptedReaction(encryptedReactionContent(message.encReactionMessage))
		}

		if message.hasStickerSyncRmrMessage {
			return .stickerSyncRMR(stickerSyncRMRContent(message.stickerSyncRmrMessage))
		}

		if message.hasPinInChatMessage {
			let pin = message.pinInChatMessage
			let action: ReceivedMessagePinAction = switch pin.type {
			case .unknownType:
				.unknown
			case .pinForAll:
				.pinForAll
			case .unpinForAll:
				.unpinForAll
			case .UNRECOGNIZED(let value):
				.unrecognized(value)
			}
			return .messagePin(ReceivedMessagePinContent(
				key: pin.hasKey ? messageKey(pin.key) : nil,
				action: action,
				senderTimestampMilliseconds: pin.hasSenderTimestampMs ? pin.senderTimestampMs : nil
			))
		}

		if message.hasKeepInChatMessage {
			let keep = message.keepInChatMessage
			let action: ReceivedMessageKeepAction = switch keep.keepType {
			case .unknown:
				.unknown
			case .keepForAll:
				.keepForAll
			case .undoKeepForAll:
				.undoKeepForAll
			case .UNRECOGNIZED(let value):
				.unrecognized(value)
			}
			return .messageKeep(ReceivedMessageKeepContent(
				key: keep.hasKey ? messageKey(keep.key) : nil,
				action: action,
				timestampMilliseconds: keep.hasTimestampMs ? keep.timestampMs : nil
			))
		}

		if message.hasNewsletterAdminInviteMessage {
			return .newsletterAdminInvite(newsletterAdminInviteContent(message.newsletterAdminInviteMessage))
		}

		if message.hasNewsletterFollowerInviteMessageV2 {
			return .newsletterFollowerInvite(newsletterFollowerInviteContent(message.newsletterFollowerInviteMessageV2))
		}

		if message.hasEncCommentMessage {
			return .encryptedComment(encryptedCommentContent(message.encCommentMessage))
		}

		if message.hasSecretEncryptedMessage {
			return .secretEncrypted(secretEncryptedContent(message.secretEncryptedMessage))
		}

		if message.hasCommentMessage {
			return .comment(commentContent(message.commentMessage))
		}

		if message.hasCallLogMesssage {
			return .callLog(callLogContent(message.callLogMesssage))
		}

		if message.hasMessageHistoryBundle {
			return .messageHistoryBundle(messageHistoryBundleContent(message.messageHistoryBundle))
		}

		if message.hasStickerPackMessage {
			return .stickerPack(stickerPackContent(message.stickerPackMessage))
		}

		if message.hasRichResponseMessage {
			return .aiRichResponse(aiRichResponseContent(message.richResponseMessage))
		}

		if message.hasStatusNotificationMessage {
			return .statusNotification(statusNotificationContent(message.statusNotificationMessage))
		}

		if message.hasStatusQuestionAnswerMessage {
			return .statusQuestionAnswer(statusQuestionAnswerContent(message.statusQuestionAnswerMessage))
		}

		if message.hasStatusQuotedMessage {
			return .statusQuoted(statusQuotedContent(message.statusQuotedMessage))
		}

		if message.hasStatusStickerInteractionMessage {
			return .statusStickerInteraction(statusStickerInteractionContent(message.statusStickerInteractionMessage))
		}

		if message.hasQuestionResponseMessage {
			let response = message.questionResponseMessage
			return .questionResponse(ReceivedQuestionResponseContent(
				key: response.hasKey ? messageKey(response.key) : nil,
				text: response.hasText ? response.text : nil
			))
		}

		if message.hasMessageHistoryNotice {
			return .messageHistoryNotice(messageHistoryNoticeContent(message.messageHistoryNotice))
		}

		if message.hasSendPaymentMessage {
			return .sendPayment(sendPaymentContent(message.sendPaymentMessage))
		}

		if message.hasRequestPaymentMessage {
			return .requestPayment(requestPaymentContent(message.requestPaymentMessage))
		}

		if message.hasDeclinePaymentRequestMessage {
			return .declinePaymentRequest(declinePaymentRequestContent(message.declinePaymentRequestMessage))
		}

		if message.hasCancelPaymentRequestMessage {
			return .cancelPaymentRequest(cancelPaymentRequestContent(message.cancelPaymentRequestMessage))
		}

		if message.hasPaymentInviteMessage {
			return .paymentInvite(paymentInviteContent(message.paymentInviteMessage))
		}

		if message.hasInvoiceMessage {
			return .invoice(invoiceContent(message.invoiceMessage))
		}

		if message.hasPlaceholderMessage {
			return .placeholder(placeholderContent(message.placeholderMessage))
		}

		if message.hasBcallMessage {
			return .businessCall(businessCallContent(message.bcallMessage))
		}

		return nil
	}

	static func messageKey(_ key: Proto_MessageKey) -> ReceivedMessageKey {
		ReceivedMessageKey(
			remoteJID: key.hasRemoteJid ? key.remoteJid : nil,
			fromMe: key.fromMe,
			id: key.hasID ? key.id : nil,
			participant: key.hasParticipant ? key.participant : nil
		)
	}

}
