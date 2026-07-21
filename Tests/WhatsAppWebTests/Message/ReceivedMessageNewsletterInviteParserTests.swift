import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message newsletter invite parser")
struct ReceivedMessageNewsletterInviteParserTests {
	@Test("parses newsletter admin invite messages")
	func parsesNewsletterAdminInviteMessages() throws {
		let thumbnail = Data([0x01, 0x02, 0x03])
		var invite = Proto_Message.NewsletterAdminInviteMessage()
		invite.newsletterJid = "120363000000000000@newsletter"
		invite.newsletterName = "Swift Updates"
		invite.jpegThumbnail = thumbnail
		invite.caption = "Join as an admin"
		invite.inviteExpiration = 1_700_555_666
		var message = Proto_Message()
		message.newsletterAdminInviteMessage = invite

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .newsletterAdminInvite(ReceivedNewsletterAdminInviteContent(
			newsletterJID: "120363000000000000@newsletter",
			newsletterName: "Swift Updates",
			caption: "Join as an admin",
			inviteExpiration: 1_700_555_666,
			jpegThumbnail: thumbnail
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent optional newsletter admin invite fields")
	func preservesAbsentOptionalNewsletterAdminInviteFields() throws {
		var invite = Proto_Message.NewsletterAdminInviteMessage()
		invite.newsletterJid = "120363000000000000@newsletter"
		var message = Proto_Message()
		message.newsletterAdminInviteMessage = invite

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .newsletterAdminInvite(ReceivedNewsletterAdminInviteContent(
			newsletterJID: "120363000000000000@newsletter",
			newsletterName: nil,
			caption: nil,
			inviteExpiration: nil,
			jpegThumbnail: nil
		)))
	}

	@Test("parses newsletter follower invite messages")
	func parsesNewsletterFollowerInviteMessages() throws {
		let thumbnail = Data([0x04, 0x05, 0x06])
		var invite = Proto_Message.NewsletterFollowerInviteMessage()
		invite.newsletterJid = "120363000000000001@newsletter"
		invite.newsletterName = "Swift Releases"
		invite.jpegThumbnail = thumbnail
		invite.caption = "Follow this channel"
		var message = Proto_Message()
		message.newsletterFollowerInviteMessageV2 = invite

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .newsletterFollowerInvite(ReceivedNewsletterFollowerInviteContent(
			newsletterJID: "120363000000000001@newsletter",
			newsletterName: "Swift Releases",
			caption: "Follow this channel",
			jpegThumbnail: thumbnail
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent optional newsletter follower invite fields")
	func preservesAbsentOptionalNewsletterFollowerInviteFields() throws {
		var invite = Proto_Message.NewsletterFollowerInviteMessage()
		invite.newsletterJid = "120363000000000001@newsletter"
		var message = Proto_Message()
		message.newsletterFollowerInviteMessageV2 = invite

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .newsletterFollowerInvite(ReceivedNewsletterFollowerInviteContent(
			newsletterJID: "120363000000000001@newsletter",
			newsletterName: nil,
			caption: nil,
			jpegThumbnail: nil
		)))
	}
}
