enum ForwardPaymentMessageMapper {
	static func invoice(from content: ReceivedInvoiceContent) -> Proto_Message {
		var invoice = Proto_Message.InvoiceMessage()
		if let note = content.note {
			invoice.note = note
		}
		if let token = content.token {
			invoice.token = token
		}
		if let attachmentType = content.attachmentType {
			invoice.attachmentType = switch attachmentType {
			case .image:
				.image
			case .pdf:
				.pdf
			case .unrecognized(let value):
				.UNRECOGNIZED(value)
			}
		}
		if let mimetype = content.attachmentMimetype {
			invoice.attachmentMimetype = mimetype
		}
		if let mediaKey = content.attachmentMediaKey {
			invoice.attachmentMediaKey = mediaKey
		}
		if let timestamp = content.attachmentMediaKeyTimestamp {
			invoice.attachmentMediaKeyTimestamp = timestamp
		}
		if let fileSHA256 = content.attachmentFileSHA256 {
			invoice.attachmentFileSha256 = fileSHA256
		}
		if let fileEncSHA256 = content.attachmentFileEncSHA256 {
			invoice.attachmentFileEncSha256 = fileEncSHA256
		}
		if let directPath = content.attachmentDirectPath {
			invoice.attachmentDirectPath = directPath
		}
		if let thumbnail = content.attachmentJpegThumbnail {
			invoice.attachmentJpegThumbnail = thumbnail
		}
		var message = Proto_Message()
		message.invoiceMessage = invoice
		return message
	}

	static func paymentInvite(from content: ReceivedPaymentInviteContent) -> Proto_Message {
		var invite = Proto_Message.PaymentInviteMessage()
		if let serviceType = content.serviceType {
			invite.serviceType = switch serviceType {
			case .unknown:
				.unknown
			case .fbpay:
				.fbpay
			case .novi:
				.novi
			case .upi:
				.upi
			case .unrecognized(let value):
				.UNRECOGNIZED(value)
			}
		}
		if let expiryTimestamp = content.expiryTimestamp {
			invite.expiryTimestamp = expiryTimestamp
		}
		var message = Proto_Message()
		message.paymentInviteMessage = invite
		return message
	}

	static func requestPayment(from content: ReceivedRequestPaymentContent) throws -> Proto_Message {
		var request = Proto_Message.RequestPaymentMessage()
		if let note = content.note {
			request.noteMessage = try noteMessage(from: note)
		}
		if let currencyCode = content.currencyCodeISO4217 {
			request.currencyCodeIso4217 = currencyCode
		}
		if let amount1000 = content.amount1000 {
			request.amount1000 = amount1000
		}
		if let requestFrom = content.requestFrom {
			request.requestFrom = requestFrom
		}
		if let expiryTimestamp = content.expiryTimestamp {
			request.expiryTimestamp = expiryTimestamp
		}
		if let amount = content.amount {
			request.amount = money(from: amount)
		}
		if let background = content.background {
			request.background = paymentBackground(from: background)
		}
		var message = Proto_Message()
		message.requestPaymentMessage = request
		return message
	}

	static func sendPayment(from content: ReceivedSendPaymentContent) throws -> Proto_Message {
		var send = Proto_Message.SendPaymentMessage()
		if let note = content.note {
			send.noteMessage = try noteMessage(from: note)
		}
		if let key = content.requestMessageKey {
			send.requestMessageKey = ForwardMessageKeyMapper.key(from: key)
		}
		if let background = content.background {
			send.background = paymentBackground(from: background)
		}
		if let transactionData = content.transactionData {
			send.transactionData = transactionData
		}
		var message = Proto_Message()
		message.sendPaymentMessage = send
		return message
	}

	static func declinePaymentRequest(from content: ReceivedPaymentRequestActionContent) -> Proto_Message {
		var decline = Proto_Message.DeclinePaymentRequestMessage()
		if let key = content.key {
			decline.key = ForwardMessageKeyMapper.key(from: key)
		}
		var message = Proto_Message()
		message.declinePaymentRequestMessage = decline
		return message
	}

	static func cancelPaymentRequest(from content: ReceivedPaymentRequestActionContent) -> Proto_Message {
		var cancel = Proto_Message.CancelPaymentRequestMessage()
		if let key = content.key {
			cancel.key = ForwardMessageKeyMapper.key(from: key)
		}
		var message = Proto_Message()
		message.cancelPaymentRequestMessage = cancel
		return message
	}

	private static func noteMessage(from content: ReceivedMessageContent) throws -> Proto_Message {
		try ForwardNestedMessageMapper.message(from: content)
	}

	private static func money(from content: ReceivedMoneyContent) -> Proto_Money {
		var money = Proto_Money()
		if let value = content.value {
			money.value = value
		}
		if let offset = content.offset {
			money.offset = offset
		}
		if let currencyCode = content.currencyCode {
			money.currencyCode = currencyCode
		}
		return money
	}

	private static func paymentBackground(from content: ReceivedPaymentBackgroundContent) -> Proto_PaymentBackground {
		var background = Proto_PaymentBackground()
		if let id = content.id {
			background.id = id
		}
		if let fileLength = content.fileLength {
			background.fileLength = fileLength
		}
		if let width = content.width {
			background.width = width
		}
		if let height = content.height {
			background.height = height
		}
		if let mimetype = content.mimetype {
			background.mimetype = mimetype
		}
		if let placeholderARGB = content.placeholderARGB {
			background.placeholderArgb = placeholderARGB
		}
		if let textARGB = content.textARGB {
			background.textArgb = textARGB
		}
		if let subtextARGB = content.subtextARGB {
			background.subtextArgb = subtextARGB
		}
		if let mediaData = content.mediaData {
			background.mediaData = paymentBackgroundMediaData(from: mediaData)
		}
		if let type = content.type {
			background.type = switch type {
			case .unknown:
				.unknown
			case .default:
				.default
			case .unrecognized(let value):
				.UNRECOGNIZED(value)
			}
		}
		return background
	}

	private static func paymentBackgroundMediaData(
		from content: ReceivedPaymentBackgroundMediaDataContent
	) -> Proto_PaymentBackground.MediaData {
		var mediaData = Proto_PaymentBackground.MediaData()
		if let mediaKey = content.mediaKey {
			mediaData.mediaKey = mediaKey
		}
		if let timestamp = content.mediaKeyTimestamp {
			mediaData.mediaKeyTimestamp = timestamp
		}
		if let fileSHA256 = content.fileSHA256 {
			mediaData.fileSha256 = fileSHA256
		}
		if let fileEncSHA256 = content.fileEncSHA256 {
			mediaData.fileEncSha256 = fileEncSHA256
		}
		if let directPath = content.directPath {
			mediaData.directPath = directPath
		}
		return mediaData
	}
}
