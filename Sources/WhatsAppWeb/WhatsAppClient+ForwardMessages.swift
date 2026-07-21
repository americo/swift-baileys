public enum WhatsAppClientForwardMessageError: Error, Equatable, Sendable {
	case unsupportedContent
}

extension WhatsAppClient {
	public func sendForwardedMessage(
		to destinationJID: String,
		message source: ReceivedMessage,
		forceForward: Bool = false,
		messageID: String? = nil
	) async throws -> String {
		let protoMessage: Proto_Message
		switch source.content {
		case .text(let text):
			protoMessage = MessageContentBuilder.text(text)
		case .textLinkPreview(let preview):
			protoMessage = MessageContentBuilder.text(OutgoingTextContent(
				text: preview.text,
				linkPreview: OutgoingLinkPreviewContent(
					matchedText: preview.matchedText,
					title: preview.title ?? "",
					description: preview.description,
					jpegThumbnail: preview.jpegThumbnail,
					thumbnail: preview.thumbnail.map {
						OutgoingLinkPreviewThumbnailContent(
							directPath: $0.directPath,
							mediaKey: $0.mediaKey,
							mediaKeyTimestamp: $0.mediaKeyTimestamp ?? 0,
							width: $0.width,
							height: $0.height,
							fileSha256: $0.fileSha256,
							fileEncSha256: $0.fileEncSha256
						)
					}
				)
			))
		case .image(let image):
			var message = Proto_Message()
			message.imageMessage = ForwardMediaMessageMapper.image(from: image)
			protoMessage = message
		case .document(let document):
			var message = Proto_Message()
			message.documentMessage = ForwardMediaMessageMapper.document(from: document)
			protoMessage = message
		case .audio(let audio):
			var message = Proto_Message()
			message.audioMessage = ForwardMediaMessageMapper.audio(from: audio)
			protoMessage = message
		case .video(let video):
			var message = Proto_Message()
			message.videoMessage = ForwardMediaMessageMapper.video(from: video)
			protoMessage = message
		case .call(let call):
			protoMessage = ForwardCallChatMessageMapper.call(from: call)
		case .chat(let chat):
			protoMessage = ForwardCallChatMessageMapper.chat(from: chat)
		case .sticker(let sticker):
			var message = Proto_Message()
			message.stickerMessage = ForwardMediaMessageMapper.sticker(from: sticker)
			protoMessage = message
		case .location(let location):
			var message = Proto_Message()
			message.locationMessage = ForwardMediaMessageMapper.location(from: location)
			protoMessage = message
		case .liveLocation(let liveLocation):
			var liveLocationMessage = Proto_Message.LiveLocationMessage()
			liveLocationMessage.degreesLatitude = liveLocation.latitude
			liveLocationMessage.degreesLongitude = liveLocation.longitude
			if let accuracyInMeters = liveLocation.accuracyInMeters {
				liveLocationMessage.accuracyInMeters = accuracyInMeters
			}
			if let speedInMetersPerSecond = liveLocation.speedInMetersPerSecond {
				liveLocationMessage.speedInMps = speedInMetersPerSecond
			}
			if let degreesClockwiseFromMagneticNorth = liveLocation.degreesClockwiseFromMagneticNorth {
				liveLocationMessage.degreesClockwiseFromMagneticNorth = degreesClockwiseFromMagneticNorth
			}
			if let caption = liveLocation.caption {
				liveLocationMessage.caption = caption
			}
			if let sequenceNumber = liveLocation.sequenceNumber {
				liveLocationMessage.sequenceNumber = sequenceNumber
			}
			if let timeOffsetSeconds = liveLocation.timeOffsetSeconds {
				liveLocationMessage.timeOffset = timeOffsetSeconds
			}
			if let jpegThumbnail = liveLocation.jpegThumbnail {
				liveLocationMessage.jpegThumbnail = jpegThumbnail
			}
			var message = Proto_Message()
			message.liveLocationMessage = liveLocationMessage
			protoMessage = message
		case .contact(let contact):
			var contactMessage = Proto_Message.ContactMessage()
			contactMessage.displayName = contact.displayName
			contactMessage.vcard = contact.vcard
			var message = Proto_Message()
			message.contactMessage = contactMessage
			protoMessage = message
		case .contacts(let contacts):
			var contactsArrayMessage = Proto_Message.ContactsArrayMessage()
			if let displayName = contacts.displayName {
				contactsArrayMessage.displayName = displayName
			}
			contactsArrayMessage.contacts = contacts.contacts.map {
				var contactMessage = Proto_Message.ContactMessage()
				contactMessage.displayName = $0.displayName
				contactMessage.vcard = $0.vcard
				return contactMessage
			}
			var message = Proto_Message()
			message.contactsArrayMessage = contactsArrayMessage
			protoMessage = message
		case .groupInvite(let invite):
			var groupInviteMessage = Proto_Message.GroupInviteMessage()
			if let groupJID = invite.groupJID {
				groupInviteMessage.groupJid = groupJID
			}
			if let inviteCode = invite.inviteCode {
				groupInviteMessage.inviteCode = inviteCode
			}
			if let inviteExpiration = invite.inviteExpiration {
				groupInviteMessage.inviteExpiration = inviteExpiration
			}
			if let groupName = invite.groupName {
				groupInviteMessage.groupName = groupName
			}
			if let caption = invite.caption {
				groupInviteMessage.caption = caption
			}
			groupInviteMessage.groupType = switch invite.groupType {
			case .default:
				.default
			case .parent:
				.parent
			case .unrecognized(let value):
				.UNRECOGNIZED(value)
			}
			if let jpegThumbnail = invite.jpegThumbnail {
				groupInviteMessage.jpegThumbnail = jpegThumbnail
			}
			var message = Proto_Message()
			message.groupInviteMessage = groupInviteMessage
			protoMessage = message
		case .event(let event):
			var eventMessage = Proto_Message.EventMessage()
			if let name = event.name {
				eventMessage.name = name
			}
			if let description = event.description {
				eventMessage.description_p = description
			}
			if let startTime = event.startTime {
				eventMessage.startTime = startTime
			}
			if let endTime = event.endTime {
				eventMessage.endTime = endTime
			}
			if let joinLink = event.joinLink {
				eventMessage.joinLink = joinLink
			}
			if let isCanceled = event.isCanceled {
				eventMessage.isCanceled = isCanceled
			}
			if let extraGuestsAllowed = event.extraGuestsAllowed {
				eventMessage.extraGuestsAllowed = extraGuestsAllowed
			}
			if let isScheduledCall = event.isScheduledCall {
				eventMessage.isScheduleCall = isScheduledCall
			}
			if let location = event.location {
				eventMessage.location = ForwardMediaMessageMapper.location(from: location)
			}
			var message = Proto_Message()
			message.eventMessage = eventMessage
			protoMessage = message
		case .encryptedEventResponse(let response):
			protoMessage = ForwardEventResponseMessageMapper.encryptedEventResponse(from: response)
		case .scheduledCallCreation(let scheduledCall):
			protoMessage = ForwardScheduledCallMessageMapper.creation(from: scheduledCall)
		case .scheduledCallEdit(let scheduledCall):
			protoMessage = ForwardScheduledCallMessageMapper.edit(from: scheduledCall)
		case .requestPhoneNumber:
			var message = Proto_Message()
			message.requestPhoneNumberMessage = Proto_Message.RequestPhoneNumberMessage()
			protoMessage = message
		case .ephemeralSetting(let setting):
			protoMessage = ForwardProtocolActionMessageMapper.ephemeralSetting(from: setting)
		case .phoneNumberShared:
			protoMessage = MessageContentBuilder.sharePhoneNumber()
		case .limitSharing(let sharing):
			protoMessage = ForwardProtocolActionMessageMapper.limitSharing(from: sharing)
		case .groupMemberLabelChange(let change):
			protoMessage = ForwardProtocolActionMessageMapper.groupMemberLabelChange(from: change)
		case .highlyStructured(let hsm):
			protoMessage = ForwardHighlyStructuredMessageMapper.message(from: hsm)
		case .pollCreation(let poll):
			var pollMessage = Proto_Message.PollCreationMessage()
			if let name = poll.name {
				pollMessage.name = name
			}
			pollMessage.options = poll.options.map {
				var option = Proto_Message.PollCreationMessage.Option()
				if let name = $0.name {
					option.optionName = name
				}
				if let hash = $0.hash {
					option.optionHash = hash
				}
				return option
			}
			if let selectableOptionsCount = poll.selectableOptionsCount {
				pollMessage.selectableOptionsCount = selectableOptionsCount
			}
			if let encryptedKey = poll.encryptedKey {
				pollMessage.encKey = encryptedKey
			}
			pollMessage.pollContentType = switch poll.contentType {
			case .unknown:
				.unknown
			case .text:
				.text
			case .image:
				.image
			case .unrecognized(let value):
				.UNRECOGNIZED(value)
			}
			pollMessage.pollType = switch poll.pollType {
			case .poll:
				.poll
			case .quiz:
				.quiz
			case .unrecognized(let value):
				.UNRECOGNIZED(value)
			}
			if let correctAnswer = poll.correctAnswer {
				var option = Proto_Message.PollCreationMessage.Option()
				if let name = correctAnswer.name {
					option.optionName = name
				}
				if let hash = correctAnswer.hash {
					option.optionHash = hash
				}
				pollMessage.correctAnswer = option
			}
			var message = Proto_Message()
			if poll.selectableOptionsCount == 1 {
				message.pollCreationMessageV3 = pollMessage
			} else {
				message.pollCreationMessage = pollMessage
			}
			protoMessage = message
		case .reaction(let reaction):
			protoMessage = ForwardReactionMessageMapper.message(from: reaction)
		case .pollUpdate(let update):
			protoMessage = ForwardPollUpdateMessageMapper.pollUpdate(from: update)
		case .pollResultSnapshot(let snapshot):
			protoMessage = ForwardPollUpdateMessageMapper.pollResultSnapshot(from: snapshot)
		case .messageRevoked(let revoked):
			protoMessage = ForwardProtocolActionMessageMapper.revoked(from: revoked)
		case .messageEdited(let edited):
			protoMessage = try ForwardProtocolActionMessageMapper.edited(from: edited)
		case .messagePin(let pin):
			protoMessage = ForwardMessageActionMessageMapper.pin(from: pin)
		case .messageKeep(let keep):
			protoMessage = ForwardMessageActionMessageMapper.keep(from: keep)
		case .newsletterAdminInvite(let invite):
			protoMessage = ForwardNewsletterInviteMessageMapper.adminInvite(from: invite)
		case .newsletterFollowerInvite(let invite):
			protoMessage = ForwardNewsletterInviteMessageMapper.followerInvite(from: invite)
		case .callLog(let callLog):
			protoMessage = ForwardCallLogMessageMapper.message(from: callLog)
		case .stickerPack(let stickerPack):
			protoMessage = ForwardStickerPackMessageMapper.message(from: stickerPack)
		case .messageHistoryBundle(let bundle):
			protoMessage = ForwardHistoryBundleMessageMapper.message(from: bundle)
		case .messageHistoryNotice(let notice):
			protoMessage = ForwardHistoryNoticeMessageMapper.message(from: notice)
		case .aiRichResponse(let response):
			protoMessage = try ForwardAIRichResponseMessageMapper.message(from: response)
		case .placeholder(let placeholder):
			protoMessage = ForwardPlaceholderMessageMapper.message(from: placeholder)
		case .businessCall(let businessCall):
			protoMessage = ForwardBusinessCallMessageMapper.message(from: businessCall)
		case .stickerSyncRMR(let stickerSync):
			protoMessage = ForwardStickerSyncMessageMapper.stickerSyncRMR(from: stickerSync)
		case .encryptedComment(let comment):
			protoMessage = ForwardEncryptedPayloadMessageMapper.encryptedComment(from: comment)
		case .encryptedReaction(let reaction):
			protoMessage = ForwardEncryptedPayloadMessageMapper.encryptedReaction(from: reaction)
		case .secretEncrypted(let secret):
			protoMessage = ForwardEncryptedPayloadMessageMapper.secretEncrypted(from: secret)
		case .invoice(let invoice):
			protoMessage = ForwardPaymentMessageMapper.invoice(from: invoice)
		case .paymentInvite(let invite):
			protoMessage = ForwardPaymentMessageMapper.paymentInvite(from: invite)
		case .requestPayment(let payment):
			protoMessage = try ForwardPaymentMessageMapper.requestPayment(from: payment)
		case .sendPayment(let payment):
			protoMessage = try ForwardPaymentMessageMapper.sendPayment(from: payment)
		case .declinePaymentRequest(let action):
			protoMessage = ForwardPaymentMessageMapper.declinePaymentRequest(from: action)
		case .cancelPaymentRequest(let action):
			protoMessage = ForwardPaymentMessageMapper.cancelPaymentRequest(from: action)
		case .comment(let comment):
			protoMessage = try ForwardCommentMessageMapper.message(from: comment)
		case .statusNotification(let status):
			protoMessage = ForwardStatusQuestionMessageMapper.statusNotification(from: status)
		case .statusQuestionAnswer(let answer):
			protoMessage = ForwardStatusQuestionMessageMapper.statusQuestionAnswer(from: answer)
		case .questionResponse(let response):
			protoMessage = ForwardStatusQuestionMessageMapper.questionResponse(from: response)
		case .statusQuoted(let quoted):
			protoMessage = ForwardStatusQuestionMessageMapper.statusQuoted(from: quoted)
		case .statusStickerInteraction(let interaction):
			protoMessage = ForwardStatusQuestionMessageMapper.statusStickerInteraction(from: interaction)
		case .order(let order):
			protoMessage = ForwardOrderMessageMapper.message(from: order)
		case .product(let product):
			protoMessage = ForwardProductMessageMapper.message(from: product)
		case .album(let album):
			protoMessage = ForwardAlbumMessageMapper.message(from: album)
		case .list(let list):
			protoMessage = ForwardListMessageMapper.message(from: list)
		case .buttonsResponse(let response):
			protoMessage = ForwardInteractiveResponseMessageMapper.buttonsResponse(from: response)
		case .listResponse(let response):
			protoMessage = ForwardInteractiveResponseMessageMapper.listResponse(from: response)
		case .templateButtonReply(let response):
			protoMessage = ForwardInteractiveResponseMessageMapper.templateButtonReply(from: response)
		case .interactiveResponse(let response):
			protoMessage = ForwardInteractiveResponseMessageMapper.interactiveResponse(from: response)
		case .buttons(let buttons):
			protoMessage = ForwardButtonsMessageMapper.message(from: buttons)
		case .interactive(let interactive):
			protoMessage = ForwardInteractiveMessageMapper.message(from: interactive)
		default:
			throw WhatsAppClientForwardMessageError.unsupportedContent
		}

		return try await sendResolvedMessage(
			to: destinationJID,
			message: MessageContentBuilder.forward(
				protoMessage,
				fromMe: source.fromMe ?? false,
				forceForward: forceForward
			),
			messageID: messageID
		)
	}
}
