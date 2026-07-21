import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward nested commerce messages")
struct WhatsAppClientForwardNestedCommerceMessageTests {
	@Test("forwards received payment notes with call and chat content")
	func forwardsReceivedPaymentNotesWithCallAndChatContent() async throws {
		let callMessage = try await forwardedRequestPaymentNote(.call(ReceivedCallContent(
			callKey: Data([0x01]),
			conversionSource: "ad",
			conversionData: Data([0x02]),
			conversionDelaySeconds: 9,
			ctwaSignals: "signals",
			ctwaPayload: Data([0x03]),
			nativeFlowCallButtonPayload: "native-flow",
			deeplinkPayload: "deeplink"
		)))

		#expect(callMessage.requestPaymentMessage.noteMessage.hasCall)
		#expect(callMessage.requestPaymentMessage.noteMessage.call.callKey == Data([0x01]))
		#expect(callMessage.requestPaymentMessage.noteMessage.call.conversionSource == "ad")

		let chatMessage = try await forwardedRequestPaymentNote(.chat(ReceivedChatContent(
			displayName: "Support",
			id: "support-chat"
		)))

		#expect(chatMessage.requestPaymentMessage.noteMessage.hasChat)
		#expect(chatMessage.requestPaymentMessage.noteMessage.chat.displayName == "Support")
		#expect(chatMessage.requestPaymentMessage.noteMessage.chat.id == "support-chat")
	}

	@Test("forwards received payment notes with newsletter and business call content")
	func forwardsReceivedPaymentNotesWithNewsletterAndBusinessCallContent() async throws {
		let adminInviteMessage = try await forwardedRequestPaymentNote(.newsletterAdminInvite(
			ReceivedNewsletterAdminInviteContent(
				newsletterJID: "120363000000000000@newsletter",
				newsletterName: "Swift Updates",
				caption: "Join as admin",
				inviteExpiration: 1_700_555_666,
				jpegThumbnail: Data([0x04, 0x05])
			)
		))

		#expect(adminInviteMessage.requestPaymentMessage.noteMessage.hasNewsletterAdminInviteMessage)
		#expect(
			adminInviteMessage.requestPaymentMessage.noteMessage.newsletterAdminInviteMessage.newsletterName
				== "Swift Updates"
		)
		#expect(adminInviteMessage.requestPaymentMessage.noteMessage.newsletterAdminInviteMessage.inviteExpiration == 1_700_555_666)

		let followerInviteMessage = try await forwardedRequestPaymentNote(.newsletterFollowerInvite(
			ReceivedNewsletterFollowerInviteContent(
				newsletterJID: "120363000000000001@newsletter",
				newsletterName: "Swift Releases",
				caption: "Follow",
				jpegThumbnail: Data([0x06, 0x07])
			)
		))

		#expect(followerInviteMessage.requestPaymentMessage.noteMessage.hasNewsletterFollowerInviteMessageV2)
		#expect(
			followerInviteMessage.requestPaymentMessage.noteMessage.newsletterFollowerInviteMessageV2.newsletterJid
				== "120363000000000001@newsletter"
		)

		let businessCallMessage = try await forwardedRequestPaymentNote(.businessCall(ReceivedBusinessCallContent(
			sessionID: "session-1",
			mediaType: .video,
			masterKey: Data([0x08, 0x09]),
			caption: "Call us"
		)))

		#expect(businessCallMessage.requestPaymentMessage.noteMessage.hasBcallMessage)
		#expect(businessCallMessage.requestPaymentMessage.noteMessage.bcallMessage.sessionID == "session-1")
		#expect(businessCallMessage.requestPaymentMessage.noteMessage.bcallMessage.mediaType == .video)
	}

	@Test("forwards received payment notes with order and album content")
	func forwardsReceivedPaymentNotesWithOrderAndAlbumContent() async throws {
		let orderMessage = try await forwardedRequestPaymentNote(.order(ReceivedOrderContent(
			orderID: "ORDER-123",
			thumbnail: Data([0x0a, 0x0b]),
			itemCount: 3,
			status: .accepted,
			surface: .catalog,
			message: "Please confirm",
			orderTitle: "Running shoes",
			sellerJID: "258840000100@s.whatsapp.net",
			token: "order-token",
			totalAmount1000: 15_990_000,
			totalCurrencyCode: "MZN",
			messageVersion: 2,
			orderRequestMessageID: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: true,
				id: "ORDER_REQUEST",
				participant: nil
			),
			catalogType: "retail"
		)))

		#expect(orderMessage.requestPaymentMessage.noteMessage.hasOrderMessage)
		#expect(orderMessage.requestPaymentMessage.noteMessage.orderMessage.orderID == "ORDER-123")
		#expect(orderMessage.requestPaymentMessage.noteMessage.orderMessage.status == .accepted)
		#expect(orderMessage.requestPaymentMessage.noteMessage.orderMessage.orderRequestMessageID.id == "ORDER_REQUEST")

		let albumMessage = try await forwardedRequestPaymentNote(.album(ReceivedAlbumContent(
			expectedImageCount: 3,
			expectedVideoCount: 2
		)))

		#expect(albumMessage.requestPaymentMessage.noteMessage.hasAlbumMessage)
		#expect(albumMessage.requestPaymentMessage.noteMessage.albumMessage.expectedImageCount == 3)
		#expect(albumMessage.requestPaymentMessage.noteMessage.albumMessage.expectedVideoCount == 2)
	}

	private func forwardedRequestPaymentNote(_ note: ReceivedMessageContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x2b]))],
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
				id: "NESTED-COMMERCE",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .requestPayment(ReceivedRequestPaymentContent(
					note: note,
					currencyCodeISO4217: "USD",
					amount1000: 12_345_000,
					requestFrom: nil,
					expiryTimestamp: nil,
					amount: nil,
					background: nil
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDNESTEDCOMMERCE"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
