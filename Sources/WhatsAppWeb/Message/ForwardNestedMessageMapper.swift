enum ForwardNestedMessageMapper {
	static func message(from content: ReceivedMessageContent) throws -> Proto_Message {
		switch content {
		case .text(let text):
			var message = Proto_Message()
			message.conversation = text
			return message
		case .textLinkPreview(let preview):
			return MessageContentBuilder.text(OutgoingTextContent(
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
			return message
		case .document(let document):
			var message = Proto_Message()
			message.documentMessage = ForwardMediaMessageMapper.document(from: document)
			return message
		case .audio(let audio):
			var message = Proto_Message()
			message.audioMessage = ForwardMediaMessageMapper.audio(from: audio)
			return message
		case .video(let video):
			var message = Proto_Message()
			message.videoMessage = ForwardMediaMessageMapper.video(from: video)
			return message
		case .call(let call):
			return ForwardCallChatMessageMapper.call(from: call)
		case .chat(let chat):
			return ForwardCallChatMessageMapper.chat(from: chat)
		case .sticker(let sticker):
			var message = Proto_Message()
			message.stickerMessage = ForwardMediaMessageMapper.sticker(from: sticker)
			return message
		case .location(let location):
			var message = Proto_Message()
			message.locationMessage = ForwardMediaMessageMapper.location(from: location)
			return message
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
			return message
		case .contact(let contact):
			var contactMessage = Proto_Message.ContactMessage()
			contactMessage.displayName = contact.displayName
			contactMessage.vcard = contact.vcard
			var message = Proto_Message()
			message.contactMessage = contactMessage
			return message
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
			return message
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
			return message
		case .encryptedEventResponse(let response):
			return ForwardEventResponseMessageMapper.encryptedEventResponse(from: response)
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
			return message
		case .requestPhoneNumber:
			var message = Proto_Message()
			message.requestPhoneNumberMessage = Proto_Message.RequestPhoneNumberMessage()
			return message
		case .ephemeralSetting(let setting):
			return ForwardProtocolActionMessageMapper.ephemeralSetting(from: setting)
		case .phoneNumberShared:
			return MessageContentBuilder.sharePhoneNumber()
		case .limitSharing(let sharing):
			return ForwardProtocolActionMessageMapper.limitSharing(from: sharing)
		case .groupMemberLabelChange(let change):
			return ForwardProtocolActionMessageMapper.groupMemberLabelChange(from: change)
		case .highlyStructured(let hsm):
			return ForwardHighlyStructuredMessageMapper.message(from: hsm)
		case .scheduledCallCreation(let scheduledCall):
			return ForwardScheduledCallMessageMapper.creation(from: scheduledCall)
		case .scheduledCallEdit(let scheduledCall):
			return ForwardScheduledCallMessageMapper.edit(from: scheduledCall)
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
			return message
		case .pollUpdate(let update):
			return ForwardPollUpdateMessageMapper.pollUpdate(from: update)
		case .pollResultSnapshot(let snapshot):
			return ForwardPollUpdateMessageMapper.pollResultSnapshot(from: snapshot)
		case .reaction(let reaction):
			return ForwardReactionMessageMapper.message(from: reaction)
		case .messageRevoked(let revoked):
			return ForwardProtocolActionMessageMapper.revoked(from: revoked)
		case .messageEdited(let edited):
			return try ForwardProtocolActionMessageMapper.edited(from: edited)
		case .messagePin(let pin):
			return ForwardMessageActionMessageMapper.pin(from: pin)
		case .messageKeep(let keep):
			return ForwardMessageActionMessageMapper.keep(from: keep)
		case .newsletterAdminInvite(let invite):
			return ForwardNewsletterInviteMessageMapper.adminInvite(from: invite)
		case .newsletterFollowerInvite(let invite):
			return ForwardNewsletterInviteMessageMapper.followerInvite(from: invite)
		case .callLog(let callLog):
			return ForwardCallLogMessageMapper.message(from: callLog)
		case .stickerPack(let stickerPack):
			return ForwardStickerPackMessageMapper.message(from: stickerPack)
		case .messageHistoryBundle(let bundle):
			return ForwardHistoryBundleMessageMapper.message(from: bundle)
		case .messageHistoryNotice(let notice):
			return ForwardHistoryNoticeMessageMapper.message(from: notice)
		case .aiRichResponse(let response):
			return try ForwardAIRichResponseMessageMapper.message(from: response)
		case .placeholder(let placeholder):
			return ForwardPlaceholderMessageMapper.message(from: placeholder)
		case .businessCall(let businessCall):
			return ForwardBusinessCallMessageMapper.message(from: businessCall)
		case .stickerSyncRMR(let stickerSync):
			return ForwardStickerSyncMessageMapper.stickerSyncRMR(from: stickerSync)
		case .encryptedComment(let comment):
			return ForwardEncryptedPayloadMessageMapper.encryptedComment(from: comment)
		case .encryptedReaction(let reaction):
			return ForwardEncryptedPayloadMessageMapper.encryptedReaction(from: reaction)
		case .secretEncrypted(let secret):
			return ForwardEncryptedPayloadMessageMapper.secretEncrypted(from: secret)
		case .invoice(let invoice):
			return ForwardPaymentMessageMapper.invoice(from: invoice)
		case .paymentInvite(let invite):
			return ForwardPaymentMessageMapper.paymentInvite(from: invite)
		case .requestPayment(let payment):
			return try ForwardPaymentMessageMapper.requestPayment(from: payment)
		case .sendPayment(let payment):
			return try ForwardPaymentMessageMapper.sendPayment(from: payment)
		case .declinePaymentRequest(let action):
			return ForwardPaymentMessageMapper.declinePaymentRequest(from: action)
		case .cancelPaymentRequest(let action):
			return ForwardPaymentMessageMapper.cancelPaymentRequest(from: action)
		case .comment(let comment):
			return try ForwardCommentMessageMapper.message(from: comment)
		case .statusNotification(let status):
			return ForwardStatusQuestionMessageMapper.statusNotification(from: status)
		case .statusQuestionAnswer(let answer):
			return ForwardStatusQuestionMessageMapper.statusQuestionAnswer(from: answer)
		case .questionResponse(let response):
			return ForwardStatusQuestionMessageMapper.questionResponse(from: response)
		case .statusQuoted(let quoted):
			return ForwardStatusQuestionMessageMapper.statusQuoted(from: quoted)
		case .statusStickerInteraction(let interaction):
			return ForwardStatusQuestionMessageMapper.statusStickerInteraction(from: interaction)
		case .order(let order):
			return ForwardOrderMessageMapper.message(from: order)
		case .product(let product):
			return ForwardProductMessageMapper.message(from: product)
		case .album(let album):
			return ForwardAlbumMessageMapper.message(from: album)
		case .list(let list):
			return ForwardListMessageMapper.message(from: list)
		case .buttonsResponse(let response):
			return ForwardInteractiveResponseMessageMapper.buttonsResponse(from: response)
		case .listResponse(let response):
			return ForwardInteractiveResponseMessageMapper.listResponse(from: response)
		case .templateButtonReply(let response):
			return ForwardInteractiveResponseMessageMapper.templateButtonReply(from: response)
		case .interactiveResponse(let response):
			return ForwardInteractiveResponseMessageMapper.interactiveResponse(from: response)
		case .buttons(let buttons):
			return ForwardButtonsMessageMapper.message(from: buttons)
		case .interactive(let interactive):
			return ForwardInteractiveMessageMapper.message(from: interactive)
		default:
			throw WhatsAppClientForwardMessageError.unsupportedContent
		}
	}
}
