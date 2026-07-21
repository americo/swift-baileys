enum MessageForwardContentBuilderError: Error, Equatable, Sendable {
	case missingContent
	case unsupportedContent
}

extension MessageContentBuilder {
	static func forward(
		_ source: Proto_Message,
		fromMe: Bool,
		forceForward: Bool = false
	) throws -> Proto_Message {
		if source.hasExtendedTextMessage {
			var message = Proto_Message()
			message.extendedTextMessage = forwardedExtendedText(source.extendedTextMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasConversation {
			var text = Proto_Message.ExtendedTextMessage()
			text.text = source.conversation
			var message = Proto_Message()
			message.extendedTextMessage = forwardedExtendedText(text, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasImageMessage {
			var message = Proto_Message()
			message.imageMessage = forwardedImage(source.imageMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasDocumentMessage {
			var message = Proto_Message()
			message.documentMessage = forwardedDocument(source.documentMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasAudioMessage {
			var message = Proto_Message()
			message.audioMessage = forwardedAudio(source.audioMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasVideoMessage {
			var message = Proto_Message()
			message.videoMessage = forwardedVideo(source.videoMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasCall {
			var message = Proto_Message()
			message.call = forwardedCall(source.call, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasStickerMessage {
			var message = Proto_Message()
			message.stickerMessage = forwardedSticker(source.stickerMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasLocationMessage {
			var message = Proto_Message()
			message.locationMessage = forwardedLocation(source.locationMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasLiveLocationMessage {
			var message = Proto_Message()
			message.liveLocationMessage = forwardedLiveLocation(source.liveLocationMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasContactMessage {
			var message = Proto_Message()
			message.contactMessage = forwardedContact(source.contactMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasContactsArrayMessage {
			var message = Proto_Message()
			message.contactsArrayMessage = forwardedContactsArray(source.contactsArrayMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasGroupInviteMessage {
			var message = Proto_Message()
			message.groupInviteMessage = forwardedGroupInvite(source.groupInviteMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasEventMessage {
			var message = Proto_Message()
			message.eventMessage = forwardedEvent(source.eventMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasRequestPhoneNumberMessage {
			var message = Proto_Message()
			message.requestPhoneNumberMessage = forwardedRequestPhoneNumber(source.requestPhoneNumberMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasTemplateMessage {
			let extracted = MessageContentNormalizer.extractedContent(source)
			if !extracted.hasTemplateMessage {
				return try forward(extracted, fromMe: fromMe, forceForward: forceForward)
			}
		}

		if source.hasHighlyStructuredMessage {
			var message = Proto_Message()
			message.highlyStructuredMessage = source.highlyStructuredMessage
			return message
		}

		if source.hasPollCreationMessage {
			var message = Proto_Message()
			message.pollCreationMessage = forwardedPollCreation(source.pollCreationMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasPollCreationMessageV2 {
			var message = Proto_Message()
			message.pollCreationMessageV2 = forwardedPollCreation(source.pollCreationMessageV2, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasPollCreationMessageV3 {
			var message = Proto_Message()
			message.pollCreationMessageV3 = forwardedPollCreation(source.pollCreationMessageV3, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasPollCreationMessageV5 {
			var message = Proto_Message()
			message.pollCreationMessageV5 = forwardedPollCreation(source.pollCreationMessageV5, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasProtocolMessage,
		   source.protocolMessage.type == .revoke
		   || source.protocolMessage.type == .messageEdit
		   || source.protocolMessage.type == .ephemeralSetting
		   || source.protocolMessage.type == .limitSharing
		   || source.protocolMessage.type == .groupMemberLabelChange {
			return try MessageForwardProtocolActionContentBuilder.message(
				from: source.protocolMessage,
				fromMe: fromMe,
				forceForward: forceForward
			)
		}

		if source.hasNewsletterAdminInviteMessage {
			var message = Proto_Message()
			message.newsletterAdminInviteMessage = forwardedNewsletterAdminInvite(
				source.newsletterAdminInviteMessage,
				fromMe: fromMe,
				forceForward: forceForward
			)
			return message
		}

		if source.hasNewsletterFollowerInviteMessageV2 {
			var message = Proto_Message()
			message.newsletterFollowerInviteMessageV2 = forwardedNewsletterFollowerInvite(
				source.newsletterFollowerInviteMessageV2,
				fromMe: fromMe,
				forceForward: forceForward
			)
			return message
		}

		if source.hasOrderMessage {
			var message = Proto_Message()
			message.orderMessage = forwardedOrder(source.orderMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasProductMessage {
			var message = Proto_Message()
			message.productMessage = forwardedProduct(source.productMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasAlbumMessage {
			var message = Proto_Message()
			message.albumMessage = forwardedAlbum(source.albumMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasListMessage {
			var message = Proto_Message()
			message.listMessage = forwardedList(source.listMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasButtonsMessage {
			var message = Proto_Message()
			message.buttonsMessage = forwardedButtons(source.buttonsMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasInteractiveMessage {
			var message = Proto_Message()
			message.interactiveMessage = forwardedInteractive(source.interactiveMessage, fromMe: fromMe, forceForward: forceForward)
			return message
		}

		if source.hasButtonsResponseMessage {
			var message = Proto_Message()
			message.buttonsResponseMessage = forwardedButtonsResponse(
				source.buttonsResponseMessage,
				fromMe: fromMe,
				forceForward: forceForward
			)
			return message
		}

		if source.hasListResponseMessage {
			var message = Proto_Message()
			message.listResponseMessage = forwardedListResponse(
				source.listResponseMessage,
				fromMe: fromMe,
				forceForward: forceForward
			)
			return message
		}

		if source.hasTemplateButtonReplyMessage {
			var message = Proto_Message()
			message.templateButtonReplyMessage = forwardedTemplateButtonReply(
				source.templateButtonReplyMessage,
				fromMe: fromMe,
				forceForward: forceForward
			)
			return message
		}

		if source.hasInteractiveResponseMessage {
			var message = Proto_Message()
			message.interactiveResponseMessage = forwardedInteractiveResponse(
				source.interactiveResponseMessage,
				fromMe: fromMe,
				forceForward: forceForward
			)
			return message
		}

		if source.hasCommentMessage {
			return try ForwardCommentMessageMapper.message(
				from: source.commentMessage,
				fromMe: fromMe,
				forceForward: forceForward
			)
		}

		if let message = MessageForwardPassThroughContentBuilder.message(from: source) {
			return message
		}

		throw MessageForwardContentBuilderError.missingContent
	}
}

private func forwardedContext(
	_ contextInfo: Proto_ContextInfo,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_ContextInfo {
	let score = contextInfo.forwardingScore + (fromMe && !forceForward ? 0 : 1)
	var contextInfo = Proto_ContextInfo()
	if score > 0 {
		contextInfo.forwardingScore = score
		contextInfo.isForwarded = true
	}

	return contextInfo
}

private func forwardedExtendedText(
	_ source: Proto_Message.ExtendedTextMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.ExtendedTextMessage {
	var text = source
	text.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return text
}

private func forwardedImage(
	_ source: Proto_Message.ImageMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.ImageMessage {
	var image = source
	image.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return image
}

private func forwardedDocument(
	_ source: Proto_Message.DocumentMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.DocumentMessage {
	var document = source
	document.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return document
}

private func forwardedAudio(
	_ source: Proto_Message.AudioMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.AudioMessage {
	var audio = source
	audio.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return audio
}

private func forwardedVideo(
	_ source: Proto_Message.VideoMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.VideoMessage {
	var video = source
	video.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return video
}

private func forwardedCall(
	_ source: Proto_Message.Call,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.Call {
	var call = source
	call.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return call
}

private func forwardedSticker(
	_ source: Proto_Message.StickerMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.StickerMessage {
	var sticker = source
	sticker.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return sticker
}

private func forwardedLocation(
	_ source: Proto_Message.LocationMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.LocationMessage {
	var location = source
	location.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return location
}

private func forwardedLiveLocation(
	_ source: Proto_Message.LiveLocationMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.LiveLocationMessage {
	var liveLocation = source
	liveLocation.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return liveLocation
}

private func forwardedContact(
	_ source: Proto_Message.ContactMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.ContactMessage {
	var contact = source
	contact.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return contact
}

private func forwardedContactsArray(
	_ source: Proto_Message.ContactsArrayMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.ContactsArrayMessage {
	var contactsArray = source
	contactsArray.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return contactsArray
}

private func forwardedGroupInvite(
	_ source: Proto_Message.GroupInviteMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.GroupInviteMessage {
	var invite = source
	invite.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return invite
}

private func forwardedEvent(
	_ source: Proto_Message.EventMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.EventMessage {
	var event = source
	event.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return event
}

private func forwardedRequestPhoneNumber(
	_ source: Proto_Message.RequestPhoneNumberMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.RequestPhoneNumberMessage {
	var request = source
	request.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return request
}

private func forwardedPollCreation(
	_ source: Proto_Message.PollCreationMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.PollCreationMessage {
	var poll = source
	poll.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return poll
}

private func forwardedNewsletterAdminInvite(
	_ source: Proto_Message.NewsletterAdminInviteMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.NewsletterAdminInviteMessage {
	var invite = source
	invite.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return invite
}

private func forwardedNewsletterFollowerInvite(
	_ source: Proto_Message.NewsletterFollowerInviteMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.NewsletterFollowerInviteMessage {
	var invite = source
	invite.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return invite
}

private func forwardedOrder(
	_ source: Proto_Message.OrderMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.OrderMessage {
	var order = source
	order.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return order
}

private func forwardedProduct(
	_ source: Proto_Message.ProductMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.ProductMessage {
	var product = source
	product.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return product
}

private func forwardedAlbum(
	_ source: Proto_Message.AlbumMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.AlbumMessage {
	var album = source
	album.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return album
}

private func forwardedList(
	_ source: Proto_Message.ListMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.ListMessage {
	var list = source
	list.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return list
}

private func forwardedButtons(
	_ source: Proto_Message.ButtonsMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.ButtonsMessage {
	var buttons = source
	buttons.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return buttons
}

private func forwardedButtonsResponse(
	_ source: Proto_Message.ButtonsResponseMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.ButtonsResponseMessage {
	var response = source
	response.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return response
}

private func forwardedListResponse(
	_ source: Proto_Message.ListResponseMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.ListResponseMessage {
	var response = source
	response.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return response
}

private func forwardedTemplateButtonReply(
	_ source: Proto_Message.TemplateButtonReplyMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.TemplateButtonReplyMessage {
	var response = source
	response.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return response
}

private func forwardedInteractiveResponse(
	_ source: Proto_Message.InteractiveResponseMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.InteractiveResponseMessage {
	var response = source
	response.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return response
}

private func forwardedInteractive(
	_ source: Proto_Message.InteractiveMessage,
	fromMe: Bool,
	forceForward: Bool
) -> Proto_Message.InteractiveMessage {
	var message = source
	message.contextInfo = forwardedContext(source.contextInfo, fromMe: fromMe, forceForward: forceForward)
	return message
}
