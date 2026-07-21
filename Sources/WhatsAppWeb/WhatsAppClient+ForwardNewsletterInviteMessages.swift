enum ForwardNewsletterInviteMessageMapper {
	static func adminInvite(from content: ReceivedNewsletterAdminInviteContent) -> Proto_Message {
		var inviteMessage = Proto_Message.NewsletterAdminInviteMessage()
		if let newsletterJID = content.newsletterJID {
			inviteMessage.newsletterJid = newsletterJID
		}
		if let newsletterName = content.newsletterName {
			inviteMessage.newsletterName = newsletterName
		}
		if let caption = content.caption {
			inviteMessage.caption = caption
		}
		if let inviteExpiration = content.inviteExpiration {
			inviteMessage.inviteExpiration = inviteExpiration
		}
		if let jpegThumbnail = content.jpegThumbnail {
			inviteMessage.jpegThumbnail = jpegThumbnail
		}

		var message = Proto_Message()
		message.newsletterAdminInviteMessage = inviteMessage
		return message
	}

	static func followerInvite(from content: ReceivedNewsletterFollowerInviteContent) -> Proto_Message {
		var inviteMessage = Proto_Message.NewsletterFollowerInviteMessage()
		if let newsletterJID = content.newsletterJID {
			inviteMessage.newsletterJid = newsletterJID
		}
		if let newsletterName = content.newsletterName {
			inviteMessage.newsletterName = newsletterName
		}
		if let caption = content.caption {
			inviteMessage.caption = caption
		}
		if let jpegThumbnail = content.jpegThumbnail {
			inviteMessage.jpegThumbnail = jpegThumbnail
		}

		var message = Proto_Message()
		message.newsletterFollowerInviteMessageV2 = inviteMessage
		return message
	}
}
