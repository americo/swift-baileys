import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward newsletter invites")
struct WhatsAppClientForwardNewsletterInviteTests {
	@Test("forwards received newsletter admin invite messages through the encrypted send path")
	func forwardsReceivedNewsletterAdminInviteMessagesThroughEncryptedSendPath() async throws {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x1e]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "NEWSADMIN1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .newsletterAdminInvite(ReceivedNewsletterAdminInviteContent(
					newsletterJID: "120363000000000000@newsletter",
					newsletterName: "Swift Updates",
					caption: "Join as an admin",
					inviteExpiration: 1_700_555_666,
					jpegThumbnail: Data([0x01, 0x02, 0x03])
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDNEWSADMIN"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.hasNewsletterAdminInviteMessage)
		#expect(message.newsletterAdminInviteMessage.newsletterJid == "120363000000000000@newsletter")
		#expect(message.newsletterAdminInviteMessage.newsletterName == "Swift Updates")
		#expect(message.newsletterAdminInviteMessage.caption == "Join as an admin")
		#expect(message.newsletterAdminInviteMessage.inviteExpiration == 1_700_555_666)
		#expect(message.newsletterAdminInviteMessage.jpegThumbnail == Data([0x01, 0x02, 0x03]))
		#expect(message.newsletterAdminInviteMessage.contextInfo.isForwarded)
		#expect(message.newsletterAdminInviteMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards received newsletter follower invite messages through the encrypted send path")
	func forwardsReceivedNewsletterFollowerInviteMessagesThroughEncryptedSendPath() async throws {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x1f]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "NEWSFOLLOW1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .newsletterFollowerInvite(ReceivedNewsletterFollowerInviteContent(
					newsletterJID: "120363000000000001@newsletter",
					newsletterName: "Swift Releases",
					caption: "Follow this channel",
					jpegThumbnail: Data([0x04, 0x05, 0x06])
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDNEWSFOLLOW"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.hasNewsletterFollowerInviteMessageV2)
		#expect(message.newsletterFollowerInviteMessageV2.newsletterJid == "120363000000000001@newsletter")
		#expect(message.newsletterFollowerInviteMessageV2.newsletterName == "Swift Releases")
		#expect(message.newsletterFollowerInviteMessageV2.caption == "Follow this channel")
		#expect(message.newsletterFollowerInviteMessageV2.jpegThumbnail == Data([0x04, 0x05, 0x06]))
		#expect(message.newsletterFollowerInviteMessageV2.contextInfo.isForwarded)
		#expect(message.newsletterFollowerInviteMessageV2.contextInfo.forwardingScore == 1)
	}
}
