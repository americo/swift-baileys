import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward payment messages")
struct WhatsAppClientForwardPaymentMessageTests {
	@Test("forwards received invoice and payment invite messages through the encrypted send path")
	func forwardsReceivedInvoiceAndPaymentInviteMessagesThroughEncryptedSendPath() async throws {
		let invoiceMessage = try await forwardedMessage(content: .invoice(ReceivedInvoiceContent(
			note: "Invoice",
			token: "invoice-token",
			attachmentType: .pdf,
			attachmentMimetype: "application/pdf",
			attachmentMediaKey: Data([0x01]),
			attachmentMediaKeyTimestamp: 1_717_900_000,
			attachmentFileSHA256: Data([0x02]),
			attachmentFileEncSHA256: Data([0x03]),
			attachmentDirectPath: "/v/t62.7118-24/invoice.enc",
			attachmentJpegThumbnail: Data([0x04])
		)))

		#expect(invoiceMessage.hasInvoiceMessage)
		#expect(invoiceMessage.invoiceMessage.note == "Invoice")
		#expect(invoiceMessage.invoiceMessage.token == "invoice-token")
		#expect(invoiceMessage.invoiceMessage.attachmentType == .pdf)
		#expect(invoiceMessage.invoiceMessage.attachmentMediaKey == Data([0x01]))

		let inviteMessage = try await forwardedMessage(content: .paymentInvite(ReceivedPaymentInviteContent(
			serviceType: .upi,
			expiryTimestamp: 1_717_800_000
		)))

		#expect(inviteMessage.hasPaymentInviteMessage)
		#expect(inviteMessage.paymentInviteMessage.serviceType == .upi)
		#expect(inviteMessage.paymentInviteMessage.expiryTimestamp == 1_717_800_000)
	}

	@Test("forwards received request and send payment messages through the encrypted send path")
	func forwardsReceivedRequestAndSendPaymentMessagesThroughEncryptedSendPath() async throws {
		let background = ReceivedPaymentBackgroundContent(
			id: "bg-1",
			fileLength: 4096,
			width: 640,
			height: 360,
			mimetype: "image/jpeg",
			placeholderARGB: 0xff000000,
			textARGB: 0xffffffff,
			subtextARGB: 0xffcccccc,
			mediaData: ReceivedPaymentBackgroundMediaDataContent(
				mediaKey: Data([0x10]),
				mediaKeyTimestamp: 1_717_900_001,
				fileSHA256: Data([0x11]),
				fileEncSHA256: Data([0x12]),
				directPath: "/v/t62.7118-24/payment-bg.enc"
			),
			type: .default
		)
		let requestMessage = try await forwardedMessage(content: .requestPayment(ReceivedRequestPaymentContent(
			note: .text("Dinner"),
			currencyCodeISO4217: "USD",
			amount1000: 12_345_000,
			requestFrom: "12025550123@s.whatsapp.net",
			expiryTimestamp: 1_717_999_999,
			amount: ReceivedMoneyContent(value: 12_345, offset: 2, currencyCode: "USD"),
			background: background
		)))

		#expect(requestMessage.hasRequestPaymentMessage)
		#expect(requestMessage.requestPaymentMessage.noteMessage.conversation == "Dinner")
		#expect(requestMessage.requestPaymentMessage.currencyCodeIso4217 == "USD")
		#expect(requestMessage.requestPaymentMessage.amount.value == 12_345)
		#expect(requestMessage.requestPaymentMessage.background.mediaData.directPath == "/v/t62.7118-24/payment-bg.enc")

		let sendMessage = try await forwardedMessage(content: .sendPayment(ReceivedSendPaymentContent(
			note: .text("Paid"),
			requestMessageKey: ReceivedMessageKey(
				remoteJID: "12025550123@s.whatsapp.net",
				fromMe: false,
				id: "REQUEST_ID",
				participant: nil
			),
			background: background,
			transactionData: "{\"status\":\"complete\"}"
		)))

		#expect(sendMessage.hasSendPaymentMessage)
		#expect(sendMessage.sendPaymentMessage.noteMessage.conversation == "Paid")
		#expect(sendMessage.sendPaymentMessage.requestMessageKey.id == "REQUEST_ID")
		#expect(sendMessage.sendPaymentMessage.transactionData == "{\"status\":\"complete\"}")
	}

	@Test("forwards received request payment notes with contact content")
	func forwardsReceivedRequestPaymentNotesWithContactContent() async throws {
		let requestMessage = try await forwardedMessage(content: .requestPayment(ReceivedRequestPaymentContent(
			note: .contact(ReceivedContactContent(
				displayName: "Maria Silva",
				vcard: "BEGIN:VCARD\nFN:Maria Silva\nTEL:+258840000000\nEND:VCARD"
			)),
			currencyCodeISO4217: "MZN",
			amount1000: 1_000,
			requestFrom: "258840000000@s.whatsapp.net",
			expiryTimestamp: nil,
			amount: nil,
			background: nil
		)))

		#expect(requestMessage.hasRequestPaymentMessage)
		#expect(requestMessage.requestPaymentMessage.noteMessage.hasContactMessage)
		#expect(requestMessage.requestPaymentMessage.noteMessage.contactMessage.displayName == "Maria Silva")
		#expect(requestMessage.requestPaymentMessage.noteMessage.contactMessage.vcard.contains("+258840000000"))
	}

	@Test("forwards received send payment notes with live location content")
	func forwardsReceivedSendPaymentNotesWithLiveLocationContent() async throws {
		let sendMessage = try await forwardedMessage(content: .sendPayment(ReceivedSendPaymentContent(
			note: .liveLocation(ReceivedLiveLocationContent(
				latitude: -25.965331,
				longitude: 32.589245,
				accuracyInMeters: 8,
				speedInMetersPerSecond: 4.5,
				degreesClockwiseFromMagneticNorth: 91,
				caption: "delivery point",
				sequenceNumber: 42,
				timeOffsetSeconds: 120,
				jpegThumbnail: Data([0x0c, 0x0d])
			)),
			requestMessageKey: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "REQUEST_LIVE_LOCATION",
				participant: nil
			),
			background: nil,
			transactionData: nil
		)))

		#expect(sendMessage.hasSendPaymentMessage)
		#expect(sendMessage.sendPaymentMessage.noteMessage.hasLiveLocationMessage)
		#expect(sendMessage.sendPaymentMessage.noteMessage.liveLocationMessage.caption == "delivery point")
		#expect(sendMessage.sendPaymentMessage.noteMessage.liveLocationMessage.sequenceNumber == 42)
		#expect(sendMessage.sendPaymentMessage.noteMessage.liveLocationMessage.jpegThumbnail == Data([0x0c, 0x0d]))
	}

	@Test("forwards received payment notes with media content")
	func forwardsReceivedPaymentNotesWithMediaContent() async throws {
		let imageMessage = try await forwardedMessage(content: .requestPayment(ReceivedRequestPaymentContent(
			note: .image(ReceivedImageContent(
				url: "https://mmg.whatsapp.net/image.enc",
				directPath: "/v/t62.7118-24/image.enc",
				mediaKey: Data([0x21]),
				fileEncSHA256: Data([0x22]),
				fileSHA256: Data([0x23]),
				fileLength: 4096,
				mediaKeyTimestamp: 1_718_000_000,
				mimetype: "image/jpeg",
				caption: "receipt",
				jpegThumbnail: Data([0x24])
			)),
			currencyCodeISO4217: "USD",
			amount1000: 12_345_000,
			requestFrom: nil,
			expiryTimestamp: nil,
			amount: nil,
			background: nil
		)))

		#expect(imageMessage.requestPaymentMessage.noteMessage.hasImageMessage)
		#expect(imageMessage.requestPaymentMessage.noteMessage.imageMessage.directPath == "/v/t62.7118-24/image.enc")
		#expect(imageMessage.requestPaymentMessage.noteMessage.imageMessage.caption == "receipt")

		let stickerMessage = try await forwardedMessage(content: .sendPayment(ReceivedSendPaymentContent(
			note: .sticker(ReceivedStickerContent(
				url: "https://mmg.whatsapp.net/sticker.enc",
				directPath: "/v/t62.7118-24/sticker.enc",
				mediaKey: Data([0x31]),
				fileEncSHA256: Data([0x32]),
				fileSHA256: Data([0x33]),
				fileLength: 2048,
				mediaKeyTimestamp: 1_718_000_001,
				mimetype: "image/webp",
				width: 512,
				height: 512,
				isAnimated: true,
				isAvatar: false,
				isAISticker: true,
				isLottie: false,
				pngThumbnail: Data([0x34])
			)),
			requestMessageKey: nil,
			background: nil,
			transactionData: nil
		)))

		#expect(stickerMessage.sendPaymentMessage.noteMessage.hasStickerMessage)
		#expect(stickerMessage.sendPaymentMessage.noteMessage.stickerMessage.directPath == "/v/t62.7118-24/sticker.enc")
		#expect(stickerMessage.sendPaymentMessage.noteMessage.stickerMessage.isAiSticker)
	}

	@Test("forwards received payment notes with message event content")
	func forwardsReceivedPaymentNotesWithMessageEventContent() async throws {
		let reactionMessage = try await forwardedMessage(content: .requestPayment(ReceivedRequestPaymentContent(
			note: .reaction(ReceivedReactionContent(
				key: ReceivedMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "REACTION_TARGET",
					participant: "258840000000@s.whatsapp.net"
				),
				text: "+1",
				groupingKey: "REACTION_TARGET",
				senderTimestampMilliseconds: 1_700_111_222_000
			)),
			currencyCodeISO4217: "USD",
			amount1000: 12_345_000,
			requestFrom: nil,
			expiryTimestamp: nil,
			amount: nil,
			background: nil
		)))

		#expect(reactionMessage.requestPaymentMessage.noteMessage.hasReactionMessage)
		#expect(reactionMessage.requestPaymentMessage.noteMessage.reactionMessage.key.id == "REACTION_TARGET")
		#expect(reactionMessage.requestPaymentMessage.noteMessage.reactionMessage.text == "+1")

		let keepMessage = try await forwardedMessage(content: .sendPayment(ReceivedSendPaymentContent(
			note: .messageKeep(ReceivedMessageKeepContent(
				key: ReceivedMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "KEEP_TARGET",
					participant: "258840000000@s.whatsapp.net"
				),
				action: .keepForAll,
				timestampMilliseconds: 1_700_333_444_000
			)),
			requestMessageKey: nil,
			background: nil,
			transactionData: nil
		)))

		#expect(keepMessage.sendPaymentMessage.noteMessage.hasKeepInChatMessage)
		#expect(keepMessage.sendPaymentMessage.noteMessage.keepInChatMessage.key.id == "KEEP_TARGET")
		#expect(keepMessage.sendPaymentMessage.noteMessage.keepInChatMessage.keepType == .keepForAll)
	}

	@Test("forwards received payment notes with sync and encrypted content")
	func forwardsReceivedPaymentNotesWithSyncAndEncryptedContent() async throws {
		let historyMessage = try await forwardedMessage(content: .requestPayment(ReceivedRequestPaymentContent(
			note: .messageHistoryNotice(ReceivedMessageHistoryNoticeContent(
				metadata: ReceivedMessageHistoryMetadataContent(
					historyReceivers: ["111@s.whatsapp.net"],
					oldestMessageTimestamp: 1_717_700_000,
					messageCount: 3
				)
			)),
			currencyCodeISO4217: "USD",
			amount1000: 12_345_000,
			requestFrom: nil,
			expiryTimestamp: nil,
			amount: nil,
			background: nil
		)))

		#expect(historyMessage.requestPaymentMessage.noteMessage.hasMessageHistoryNotice)
		#expect(
			historyMessage.requestPaymentMessage.noteMessage.messageHistoryNotice.messageHistoryMetadata.messageCount == 3
		)

		let stickerSyncMessage = try await forwardedMessage(content: .sendPayment(ReceivedSendPaymentContent(
			note: .stickerSyncRMR(ReceivedStickerSyncRMRContent(
				filehash: ["hash-a", "hash-b"],
				rmrSource: "rmr-source",
				requestTimestamp: 1_717_171_717
			)),
			requestMessageKey: nil,
			background: nil,
			transactionData: nil
		)))

		#expect(stickerSyncMessage.sendPaymentMessage.noteMessage.hasStickerSyncRmrMessage)
		#expect(stickerSyncMessage.sendPaymentMessage.noteMessage.stickerSyncRmrMessage.filehash == ["hash-a", "hash-b"])

		let encryptedMessage = try await forwardedMessage(content: .requestPayment(ReceivedRequestPaymentContent(
			note: .encryptedComment(ReceivedEncryptedCommentContent(
				targetMessageKey: ReceivedMessageKey(
					remoteJID: "status@broadcast",
					fromMe: false,
					id: "encrypted-target",
					participant: nil
				),
				encryptedPayload: Data([0x01, 0x02]),
				encryptedIV: Data([0x03, 0x04])
			)),
			currencyCodeISO4217: "USD",
			amount1000: 12_345_000,
			requestFrom: nil,
			expiryTimestamp: nil,
			amount: nil,
			background: nil
		)))

		#expect(encryptedMessage.requestPaymentMessage.noteMessage.hasEncCommentMessage)
		#expect(encryptedMessage.requestPaymentMessage.noteMessage.encCommentMessage.targetMessageKey.id == "encrypted-target")
	}

	@Test("forwards received payment notes with status and interactive content")
	func forwardsReceivedPaymentNotesWithStatusAndInteractiveContent() async throws {
		let statusMessage = try await forwardedMessage(content: .requestPayment(ReceivedRequestPaymentContent(
			note: .statusQuestionAnswer(ReceivedStatusQuestionAnswerContent(
				key: ReceivedMessageKey(
					remoteJID: "status@broadcast",
					fromMe: false,
					id: "STATUS_TARGET",
					participant: "258840000000@s.whatsapp.net"
				),
				text: "answer"
			)),
			currencyCodeISO4217: "USD",
			amount1000: 12_345_000,
			requestFrom: nil,
			expiryTimestamp: nil,
			amount: nil,
			background: nil
		)))

		#expect(statusMessage.requestPaymentMessage.noteMessage.hasStatusQuestionAnswerMessage)
		#expect(statusMessage.requestPaymentMessage.noteMessage.statusQuestionAnswerMessage.text == "answer")

		let buttonResponseMessage = try await forwardedMessage(content: .sendPayment(ReceivedSendPaymentContent(
			note: .buttonsResponse(ReceivedButtonsResponseContent(
				selectedButtonID: "confirm",
				selectedDisplayText: "Confirm",
				type: .displayText
			)),
			requestMessageKey: nil,
			background: nil,
			transactionData: nil
		)))

		#expect(buttonResponseMessage.sendPaymentMessage.noteMessage.hasButtonsResponseMessage)
		#expect(buttonResponseMessage.sendPaymentMessage.noteMessage.buttonsResponseMessage.selectedButtonID == "confirm")

		let listResponseMessage = try await forwardedMessage(content: .requestPayment(ReceivedRequestPaymentContent(
			note: .listResponse(ReceivedListResponseContent(
				title: "Shipping",
				listType: .singleSelect,
				selectedRowID: "pickup",
				description: "Pickup"
			)),
			currencyCodeISO4217: "USD",
			amount1000: 12_345_000,
			requestFrom: nil,
			expiryTimestamp: nil,
			amount: nil,
			background: nil
		)))

		#expect(listResponseMessage.requestPaymentMessage.noteMessage.hasListResponseMessage)
		#expect(listResponseMessage.requestPaymentMessage.noteMessage.listResponseMessage.singleSelectReply.selectedRowID == "pickup")
	}

	@Test("forwards received payment notes with product list content")
	func forwardsReceivedPaymentNotesWithProductListContent() async throws {
		let listMessage = try await forwardedMessage(content: .sendPayment(ReceivedSendPaymentContent(
			note: .list(ReceivedListContent(
				title: "Options",
				description: "Choose one",
				buttonText: "Open",
				listType: .singleSelect,
				sections: [
					ReceivedListSectionContent(
						title: "Main",
						rows: [ReceivedListRowContent(title: "Pickup", description: "Today", rowID: "pickup")]
					)
				],
				productListInfo: nil,
				footerText: "Footer"
			)),
			requestMessageKey: nil,
			background: nil,
			transactionData: nil
		)))

		#expect(listMessage.sendPaymentMessage.noteMessage.hasListMessage)
		#expect(listMessage.sendPaymentMessage.noteMessage.listMessage.sections[0].rows[0].rowID == "pickup")

		let productMessage = try await forwardedMessage(content: .requestPayment(ReceivedRequestPaymentContent(
			note: .product(ReceivedProductContent(
				product: nil,
				businessOwnerJID: "258840000000@s.whatsapp.net",
				catalog: nil,
				body: "Product body",
				footer: "Product footer"
			)),
			currencyCodeISO4217: "USD",
			amount1000: 12_345_000,
			requestFrom: nil,
			expiryTimestamp: nil,
			amount: nil,
			background: nil
		)))

		#expect(productMessage.requestPaymentMessage.noteMessage.hasProductMessage)
		#expect(productMessage.requestPaymentMessage.noteMessage.productMessage.businessOwnerJid == "258840000000@s.whatsapp.net")
		#expect(productMessage.requestPaymentMessage.noteMessage.productMessage.body == "Product body")
	}

	@Test("forwards received payment request action messages through the encrypted send path")
	func forwardsReceivedPaymentRequestActionMessagesThroughEncryptedSendPath() async throws {
		let key = ReceivedMessageKey(
			remoteJID: "12025550123@s.whatsapp.net",
			fromMe: true,
			id: "PAYMENT_REQUEST_ID",
			participant: "12025550124@s.whatsapp.net"
		)
		let declineMessage = try await forwardedMessage(content: .declinePaymentRequest(
			ReceivedPaymentRequestActionContent(key: key)
		))

		#expect(declineMessage.hasDeclinePaymentRequestMessage)
		#expect(declineMessage.declinePaymentRequestMessage.key.id == "PAYMENT_REQUEST_ID")
		#expect(declineMessage.declinePaymentRequestMessage.key.participant == "12025550124@s.whatsapp.net")

		let cancelMessage = try await forwardedMessage(content: .cancelPaymentRequest(
			ReceivedPaymentRequestActionContent(key: key)
		))

		#expect(cancelMessage.hasCancelPaymentRequestMessage)
		#expect(cancelMessage.cancelPaymentRequestMessage.key.remoteJid == "12025550123@s.whatsapp.net")
		#expect(cancelMessage.cancelPaymentRequestMessage.key.fromMe)
	}

	private func forwardedMessage(content: ReceivedMessageContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x2a]))],
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
				id: "PAYMENT1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDEDPAYMENT"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
