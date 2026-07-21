import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Message forward payment content builder")
struct MessageForwardPaymentContentBuilderTests {
	@Test("forwards payment and invoice messages as pass-through content")
	func forwardsPaymentAndInvoiceMessagesAsPassThroughContent() throws {
		var invoice = Proto_Message.InvoiceMessage()
		invoice.note = "Invoice"
		invoice.token = "invoice-token"
		invoice.attachmentType = .pdf
		var invoiceSource = Proto_Message()
		invoiceSource.invoiceMessage = invoice

		let invoiceMessage = try MessageContentBuilder.forward(invoiceSource, fromMe: false)

		#expect(invoiceMessage.hasInvoiceMessage)
		#expect(invoiceMessage.invoiceMessage.note == "Invoice")
		#expect(invoiceMessage.invoiceMessage.token == "invoice-token")
		#expect(invoiceMessage.invoiceMessage.attachmentType == .pdf)

		var invite = Proto_Message.PaymentInviteMessage()
		invite.serviceType = .upi
		invite.expiryTimestamp = 1_717_800_000
		var inviteSource = Proto_Message()
		inviteSource.paymentInviteMessage = invite

		let inviteMessage = try MessageContentBuilder.forward(inviteSource, fromMe: false)

		#expect(inviteMessage.hasPaymentInviteMessage)
		#expect(inviteMessage.paymentInviteMessage.serviceType == .upi)
		#expect(inviteMessage.paymentInviteMessage.expiryTimestamp == 1_717_800_000)

		var request = Proto_Message.RequestPaymentMessage()
		request.currencyCodeIso4217 = "USD"
		request.amount1000 = 12_345_000
		var requestSource = Proto_Message()
		requestSource.requestPaymentMessage = request

		let requestMessage = try MessageContentBuilder.forward(requestSource, fromMe: false)

		#expect(requestMessage.hasRequestPaymentMessage)
		#expect(requestMessage.requestPaymentMessage.currencyCodeIso4217 == "USD")
		#expect(requestMessage.requestPaymentMessage.amount1000 == 12_345_000)

		var send = Proto_Message.SendPaymentMessage()
		send.transactionData = "{\"status\":\"complete\"}"
		var sendSource = Proto_Message()
		sendSource.sendPaymentMessage = send

		let sendMessage = try MessageContentBuilder.forward(sendSource, fromMe: false)

		#expect(sendMessage.hasSendPaymentMessage)
		#expect(sendMessage.sendPaymentMessage.transactionData == "{\"status\":\"complete\"}")
	}

	@Test("forwards payment request action messages as pass-through content")
	func forwardsPaymentRequestActionMessagesAsPassThroughContent() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "12025550123@s.whatsapp.net"
		key.fromMe = true
		key.id = "PAYMENT_REQUEST_ID"

		var decline = Proto_Message.DeclinePaymentRequestMessage()
		decline.key = key
		var declineSource = Proto_Message()
		declineSource.declinePaymentRequestMessage = decline

		let declineMessage = try MessageContentBuilder.forward(declineSource, fromMe: false)

		#expect(declineMessage.hasDeclinePaymentRequestMessage)
		#expect(declineMessage.declinePaymentRequestMessage.key.id == "PAYMENT_REQUEST_ID")

		var cancel = Proto_Message.CancelPaymentRequestMessage()
		cancel.key = key
		var cancelSource = Proto_Message()
		cancelSource.cancelPaymentRequestMessage = cancel

		let cancelMessage = try MessageContentBuilder.forward(cancelSource, fromMe: false)

		#expect(cancelMessage.hasCancelPaymentRequestMessage)
		#expect(cancelMessage.cancelPaymentRequestMessage.key.remoteJid == "12025550123@s.whatsapp.net")
	}
}
