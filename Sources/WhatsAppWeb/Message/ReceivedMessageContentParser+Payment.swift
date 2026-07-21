extension ReceivedMessageContentParser {
	static func invoiceContent(_ invoice: Proto_Message.InvoiceMessage) -> ReceivedInvoiceContent {
		ReceivedInvoiceContent(
			note: invoice.hasNote ? invoice.note : nil,
			token: invoice.hasToken ? invoice.token : nil,
			attachmentType: invoice.hasAttachmentType ? invoiceAttachmentType(invoice.attachmentType) : nil,
			attachmentMimetype: invoice.hasAttachmentMimetype ? invoice.attachmentMimetype : nil,
			attachmentMediaKey: invoice.hasAttachmentMediaKey ? invoice.attachmentMediaKey : nil,
			attachmentMediaKeyTimestamp: invoice.hasAttachmentMediaKeyTimestamp
				? invoice.attachmentMediaKeyTimestamp
				: nil,
			attachmentFileSHA256: invoice.hasAttachmentFileSha256 ? invoice.attachmentFileSha256 : nil,
			attachmentFileEncSHA256: invoice.hasAttachmentFileEncSha256 ? invoice.attachmentFileEncSha256 : nil,
			attachmentDirectPath: invoice.hasAttachmentDirectPath ? invoice.attachmentDirectPath : nil,
			attachmentJpegThumbnail: invoice.hasAttachmentJpegThumbnail ? invoice.attachmentJpegThumbnail : nil
		)
	}

	static func paymentInviteContent(_ invite: Proto_Message.PaymentInviteMessage) -> ReceivedPaymentInviteContent {
		ReceivedPaymentInviteContent(
			serviceType: invite.hasServiceType ? paymentInviteServiceType(invite.serviceType) : nil,
			expiryTimestamp: invite.hasExpiryTimestamp ? invite.expiryTimestamp : nil
		)
	}

	static func sendPaymentContent(_ send: Proto_Message.SendPaymentMessage) -> ReceivedSendPaymentContent {
		ReceivedSendPaymentContent(
			note: send.hasNoteMessage ? parse(send.noteMessage) : nil,
			requestMessageKey: send.hasRequestMessageKey ? messageKey(send.requestMessageKey) : nil,
			background: send.hasBackground ? paymentBackgroundContent(send.background) : nil,
			transactionData: send.hasTransactionData ? send.transactionData : nil
		)
	}

	static func requestPaymentContent(_ request: Proto_Message.RequestPaymentMessage) -> ReceivedRequestPaymentContent {
		ReceivedRequestPaymentContent(
			note: request.hasNoteMessage ? parse(request.noteMessage) : nil,
			currencyCodeISO4217: request.hasCurrencyCodeIso4217 ? request.currencyCodeIso4217 : nil,
			amount1000: request.hasAmount1000 ? request.amount1000 : nil,
			requestFrom: request.hasRequestFrom ? request.requestFrom : nil,
			expiryTimestamp: request.hasExpiryTimestamp ? request.expiryTimestamp : nil,
			amount: request.hasAmount ? moneyContent(request.amount) : nil,
			background: request.hasBackground ? paymentBackgroundContent(request.background) : nil
		)
	}

	static func declinePaymentRequestContent(
		_ decline: Proto_Message.DeclinePaymentRequestMessage
	) -> ReceivedPaymentRequestActionContent {
		ReceivedPaymentRequestActionContent(key: decline.hasKey ? messageKey(decline.key) : nil)
	}

	static func cancelPaymentRequestContent(
		_ cancel: Proto_Message.CancelPaymentRequestMessage
	) -> ReceivedPaymentRequestActionContent {
		ReceivedPaymentRequestActionContent(key: cancel.hasKey ? messageKey(cancel.key) : nil)
	}

	private static func invoiceAttachmentType(
		_ attachmentType: Proto_Message.InvoiceMessage.AttachmentType
	) -> ReceivedInvoiceAttachmentType {
		switch attachmentType {
		case .image:
			.image
		case .pdf:
			.pdf
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	private static func moneyContent(_ money: Proto_Money) -> ReceivedMoneyContent {
		ReceivedMoneyContent(
			value: money.hasValue ? money.value : nil,
			offset: money.hasOffset ? money.offset : nil,
			currencyCode: money.hasCurrencyCode ? money.currencyCode : nil
		)
	}

	private static func paymentBackgroundContent(_ background: Proto_PaymentBackground) -> ReceivedPaymentBackgroundContent {
		ReceivedPaymentBackgroundContent(
			id: background.hasID ? background.id : nil,
			fileLength: background.hasFileLength ? background.fileLength : nil,
			width: background.hasWidth ? background.width : nil,
			height: background.hasHeight ? background.height : nil,
			mimetype: background.hasMimetype ? background.mimetype : nil,
			placeholderARGB: background.hasPlaceholderArgb ? background.placeholderArgb : nil,
			textARGB: background.hasTextArgb ? background.textArgb : nil,
			subtextARGB: background.hasSubtextArgb ? background.subtextArgb : nil,
			mediaData: background.hasMediaData ? paymentBackgroundMediaDataContent(background.mediaData) : nil,
			type: background.hasType ? paymentBackgroundType(background.type) : nil
		)
	}

	private static func paymentBackgroundMediaDataContent(
		_ mediaData: Proto_PaymentBackground.MediaData
	) -> ReceivedPaymentBackgroundMediaDataContent {
		ReceivedPaymentBackgroundMediaDataContent(
			mediaKey: mediaData.hasMediaKey ? mediaData.mediaKey : nil,
			mediaKeyTimestamp: mediaData.hasMediaKeyTimestamp ? mediaData.mediaKeyTimestamp : nil,
			fileSHA256: mediaData.hasFileSha256 ? mediaData.fileSha256 : nil,
			fileEncSHA256: mediaData.hasFileEncSha256 ? mediaData.fileEncSha256 : nil,
			directPath: mediaData.hasDirectPath ? mediaData.directPath : nil
		)
	}

	private static func paymentBackgroundType(
		_ type: Proto_PaymentBackground.TypeEnum
	) -> ReceivedPaymentBackgroundType {
		switch type {
		case .unknown:
			.unknown
		case .default:
			.default
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	private static func paymentInviteServiceType(
		_ serviceType: Proto_Message.PaymentInviteMessage.ServiceType
	) -> ReceivedPaymentInviteServiceType {
		switch serviceType {
		case .unknown:
			.unknown
		case .fbpay:
			.fbpay
		case .novi:
			.novi
		case .upi:
			.upi
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}
}
