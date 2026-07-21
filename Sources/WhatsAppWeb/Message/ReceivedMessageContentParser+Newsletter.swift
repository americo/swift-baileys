extension ReceivedMessageContentParser {
	static func newsletterAdminInviteContent(
		_ invite: Proto_Message.NewsletterAdminInviteMessage
	) -> ReceivedNewsletterAdminInviteContent {
		ReceivedNewsletterAdminInviteContent(
			newsletterJID: invite.hasNewsletterJid ? invite.newsletterJid : nil,
			newsletterName: invite.hasNewsletterName ? invite.newsletterName : nil,
			caption: invite.hasCaption ? invite.caption : nil,
			inviteExpiration: invite.hasInviteExpiration ? invite.inviteExpiration : nil,
			jpegThumbnail: invite.hasJpegThumbnail ? invite.jpegThumbnail : nil
		)
	}

	static func newsletterFollowerInviteContent(
		_ invite: Proto_Message.NewsletterFollowerInviteMessage
	) -> ReceivedNewsletterFollowerInviteContent {
		ReceivedNewsletterFollowerInviteContent(
			newsletterJID: invite.hasNewsletterJid ? invite.newsletterJid : nil,
			newsletterName: invite.hasNewsletterName ? invite.newsletterName : nil,
			caption: invite.hasCaption ? invite.caption : nil,
			jpegThumbnail: invite.hasJpegThumbnail ? invite.jpegThumbnail : nil
		)
	}
}
