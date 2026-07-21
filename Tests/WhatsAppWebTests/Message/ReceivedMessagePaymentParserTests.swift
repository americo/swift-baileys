import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message payment parser")
struct ReceivedMessagePaymentParserTests {
	@Test("parses invoice messages")
	func parsesInvoiceMessages() throws {
		let mediaKey = Data([0x01, 0x02, 0x03])
		let fileSHA256 = Data([0x04, 0x05, 0x06])
		let fileEncSHA256 = Data([0x07, 0x08, 0x09])
		let thumbnail = Data([0x0a, 0x0b])
		var invoice = Proto_Message.InvoiceMessage()
		invoice.note = "Pagamento da encomenda"
		invoice.token = "invoice-token"
		invoice.attachmentType = .pdf
		invoice.attachmentMimetype = "application/pdf"
		invoice.attachmentMediaKey = mediaKey
		invoice.attachmentMediaKeyTimestamp = 1_717_900_000
		invoice.attachmentFileSha256 = fileSHA256
		invoice.attachmentFileEncSha256 = fileEncSHA256
		invoice.attachmentDirectPath = "/v/t62.7118-24/invoice.enc"
		invoice.attachmentJpegThumbnail = thumbnail
		var message = Proto_Message()
		message.invoiceMessage = invoice

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .invoice(ReceivedInvoiceContent(
			note: "Pagamento da encomenda",
			token: "invoice-token",
			attachmentType: .pdf,
			attachmentMimetype: "application/pdf",
			attachmentMediaKey: mediaKey,
			attachmentMediaKeyTimestamp: 1_717_900_000,
			attachmentFileSHA256: fileSHA256,
			attachmentFileEncSHA256: fileEncSHA256,
			attachmentDirectPath: "/v/t62.7118-24/invoice.enc",
			attachmentJpegThumbnail: thumbnail
		)))
		#expect(try content.mediaDownloadRequest() == MediaDownloadRequest(
			url: try #require(URL(string: "https://mmg.whatsapp.net/v/t62.7118-24/invoice.enc")),
			mediaKey: mediaKey,
			mediaType: .document,
			fileEncSHA256: fileEncSHA256,
			fileSHA256: fileSHA256
		))
	}

	@Test("preserves absent invoice fields")
	func preservesAbsentInvoiceFields() throws {
		var message = Proto_Message()
		message.invoiceMessage = Proto_Message.InvoiceMessage()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .invoice(ReceivedInvoiceContent(
			note: nil,
			token: nil,
			attachmentType: nil,
			attachmentMimetype: nil,
			attachmentMediaKey: nil,
			attachmentMediaKeyTimestamp: nil,
			attachmentFileSHA256: nil,
			attachmentFileEncSHA256: nil,
			attachmentDirectPath: nil,
			attachmentJpegThumbnail: nil
		)))
	}

	@Test("parses payment invite messages")
	func parsesPaymentInviteMessages() throws {
		var invite = Proto_Message.PaymentInviteMessage()
		invite.serviceType = .upi
		invite.expiryTimestamp = 1_717_800_000
		var message = Proto_Message()
		message.paymentInviteMessage = invite

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .paymentInvite(ReceivedPaymentInviteContent(
			serviceType: .upi,
			expiryTimestamp: 1_717_800_000
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent payment invite fields")
	func preservesAbsentPaymentInviteFields() throws {
		var message = Proto_Message()
		message.paymentInviteMessage = Proto_Message.PaymentInviteMessage()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .paymentInvite(ReceivedPaymentInviteContent(
			serviceType: nil,
			expiryTimestamp: nil
		)))
	}

	@Test("parses request payment messages")
	func parsesRequestPaymentMessages() throws {
		let mediaKey = Data([0x10, 0x11])
		let fileSHA256 = Data([0x12, 0x13])
		let fileEncSHA256 = Data([0x14, 0x15])
		var mediaData = Proto_PaymentBackground.MediaData()
		mediaData.mediaKey = mediaKey
		mediaData.mediaKeyTimestamp = 1_717_900_001
		mediaData.fileSha256 = fileSHA256
		mediaData.fileEncSha256 = fileEncSHA256
		mediaData.directPath = "/v/t62.7118-24/payment-bg.enc"
		var background = Proto_PaymentBackground()
		background.id = "bg-1"
		background.fileLength = 4096
		background.width = 640
		background.height = 360
		background.mimetype = "image/jpeg"
		background.placeholderArgb = 0xff000000
		background.textArgb = 0xffffffff
		background.subtextArgb = 0xffcccccc
		background.mediaData = mediaData
		background.type = .default
		var amount = Proto_Money()
		amount.value = 12_345
		amount.offset = 2
		amount.currencyCode = "USD"
		var note = Proto_Message()
		note.conversation = "Dinner"
		var request = Proto_Message.RequestPaymentMessage()
		request.noteMessage = note
		request.currencyCodeIso4217 = "USD"
		request.amount1000 = 12_345_000
		request.requestFrom = "12025550123@s.whatsapp.net"
		request.expiryTimestamp = 1_717_999_999
		request.amount = amount
		request.background = background
		var message = Proto_Message()
		message.requestPaymentMessage = request

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .requestPayment(ReceivedRequestPaymentContent(
			note: .text("Dinner"),
			currencyCodeISO4217: "USD",
			amount1000: 12_345_000,
			requestFrom: "12025550123@s.whatsapp.net",
			expiryTimestamp: 1_717_999_999,
			amount: ReceivedMoneyContent(value: 12_345, offset: 2, currencyCode: "USD"),
			background: ReceivedPaymentBackgroundContent(
				id: "bg-1",
				fileLength: 4096,
				width: 640,
				height: 360,
				mimetype: "image/jpeg",
				placeholderARGB: 0xff000000,
				textARGB: 0xffffffff,
				subtextARGB: 0xffcccccc,
				mediaData: ReceivedPaymentBackgroundMediaDataContent(
					mediaKey: mediaKey,
					mediaKeyTimestamp: 1_717_900_001,
					fileSHA256: fileSHA256,
					fileEncSHA256: fileEncSHA256,
					directPath: "/v/t62.7118-24/payment-bg.enc"
				),
				type: .default
			)
		)))
		#expect(try content.mediaDownloadRequest() == MediaDownloadRequest(
			url: try #require(URL(string: "https://mmg.whatsapp.net/v/t62.7118-24/payment-bg.enc")),
			mediaKey: mediaKey,
			mediaType: .image,
			fileEncSHA256: fileEncSHA256,
			fileSHA256: fileSHA256
		))
	}

	@Test("parses send payment messages")
	func parsesSendPaymentMessages() throws {
		var requestKey = Proto_MessageKey()
		requestKey.remoteJid = "12025550123@s.whatsapp.net"
		requestKey.id = "REQUEST_ID"
		var note = Proto_Message()
		note.conversation = "Paid"
		var send = Proto_Message.SendPaymentMessage()
		send.noteMessage = note
		send.requestMessageKey = requestKey
		send.transactionData = "{\"status\":\"complete\"}"
		var message = Proto_Message()
		message.sendPaymentMessage = send

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .sendPayment(ReceivedSendPaymentContent(
			note: .text("Paid"),
			requestMessageKey: ReceivedMessageKey(
				remoteJID: "12025550123@s.whatsapp.net",
				fromMe: false,
				id: "REQUEST_ID",
				participant: nil
			),
			background: nil,
			transactionData: "{\"status\":\"complete\"}"
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses decline payment request messages")
	func parsesDeclinePaymentRequestMessages() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "12025550123@s.whatsapp.net"
		key.fromMe = true
		key.id = "PAYMENT_REQUEST_ID"
		key.participant = "12025550124@s.whatsapp.net"
		var decline = Proto_Message.DeclinePaymentRequestMessage()
		decline.key = key
		var message = Proto_Message()
		message.declinePaymentRequestMessage = decline

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .declinePaymentRequest(ReceivedPaymentRequestActionContent(
			key: ReceivedMessageKey(
				remoteJID: "12025550123@s.whatsapp.net",
				fromMe: true,
				id: "PAYMENT_REQUEST_ID",
				participant: "12025550124@s.whatsapp.net"
			)
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses cancel payment request messages without a key")
	func parsesCancelPaymentRequestMessagesWithoutKey() throws {
		var message = Proto_Message()
		message.cancelPaymentRequestMessage = Proto_Message.CancelPaymentRequestMessage()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .cancelPaymentRequest(ReceivedPaymentRequestActionContent(key: nil)))
		#expect(try content.mediaDownloadRequest() == nil)
	}
}
