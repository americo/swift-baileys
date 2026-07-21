import Foundation

public enum ReceivedInvoiceAttachmentType: Equatable, Sendable {
	case image
	case pdf
	case unrecognized(Int)
}

public struct ReceivedInvoiceContent: Equatable, Sendable {
	public let note: String?
	public let token: String?
	public let attachmentType: ReceivedInvoiceAttachmentType?
	public let attachmentMimetype: String?
	public let attachmentMediaKey: Data?
	public let attachmentMediaKeyTimestamp: Int64?
	public let attachmentFileSHA256: Data?
	public let attachmentFileEncSHA256: Data?
	public let attachmentDirectPath: String?
	public let attachmentJpegThumbnail: Data?

	public init(
		note: String?,
		token: String?,
		attachmentType: ReceivedInvoiceAttachmentType?,
		attachmentMimetype: String?,
		attachmentMediaKey: Data?,
		attachmentMediaKeyTimestamp: Int64?,
		attachmentFileSHA256: Data?,
		attachmentFileEncSHA256: Data?,
		attachmentDirectPath: String?,
		attachmentJpegThumbnail: Data?
	) {
		self.note = note
		self.token = token
		self.attachmentType = attachmentType
		self.attachmentMimetype = attachmentMimetype
		self.attachmentMediaKey = attachmentMediaKey
		self.attachmentMediaKeyTimestamp = attachmentMediaKeyTimestamp
		self.attachmentFileSHA256 = attachmentFileSHA256
		self.attachmentFileEncSHA256 = attachmentFileEncSHA256
		self.attachmentDirectPath = attachmentDirectPath
		self.attachmentJpegThumbnail = attachmentJpegThumbnail
	}
}

public enum ReceivedPaymentInviteServiceType: Equatable, Sendable {
	case unknown
	case fbpay
	case novi
	case upi
	case unrecognized(Int)
}

public struct ReceivedPaymentInviteContent: Equatable, Sendable {
	public let serviceType: ReceivedPaymentInviteServiceType?
	public let expiryTimestamp: Int64?

	public init(serviceType: ReceivedPaymentInviteServiceType?, expiryTimestamp: Int64?) {
		self.serviceType = serviceType
		self.expiryTimestamp = expiryTimestamp
	}
}

public struct ReceivedMoneyContent: Equatable, Sendable {
	public let value: Int64?
	public let offset: UInt32?
	public let currencyCode: String?

	public init(value: Int64?, offset: UInt32?, currencyCode: String?) {
		self.value = value
		self.offset = offset
		self.currencyCode = currencyCode
	}
}

public enum ReceivedPaymentBackgroundType: Equatable, Sendable {
	case unknown
	case `default`
	case unrecognized(Int)
}

public struct ReceivedPaymentBackgroundMediaDataContent: Equatable, Sendable {
	public let mediaKey: Data?
	public let mediaKeyTimestamp: Int64?
	public let fileSHA256: Data?
	public let fileEncSHA256: Data?
	public let directPath: String?

	public init(
		mediaKey: Data?,
		mediaKeyTimestamp: Int64?,
		fileSHA256: Data?,
		fileEncSHA256: Data?,
		directPath: String?
	) {
		self.mediaKey = mediaKey
		self.mediaKeyTimestamp = mediaKeyTimestamp
		self.fileSHA256 = fileSHA256
		self.fileEncSHA256 = fileEncSHA256
		self.directPath = directPath
	}
}

public struct ReceivedPaymentBackgroundContent: Equatable, Sendable {
	public let id: String?
	public let fileLength: UInt64?
	public let width: UInt32?
	public let height: UInt32?
	public let mimetype: String?
	public let placeholderARGB: UInt32?
	public let textARGB: UInt32?
	public let subtextARGB: UInt32?
	public let mediaData: ReceivedPaymentBackgroundMediaDataContent?
	public let type: ReceivedPaymentBackgroundType?

	public init(
		id: String?,
		fileLength: UInt64?,
		width: UInt32?,
		height: UInt32?,
		mimetype: String?,
		placeholderARGB: UInt32?,
		textARGB: UInt32?,
		subtextARGB: UInt32?,
		mediaData: ReceivedPaymentBackgroundMediaDataContent?,
		type: ReceivedPaymentBackgroundType?
	) {
		self.id = id
		self.fileLength = fileLength
		self.width = width
		self.height = height
		self.mimetype = mimetype
		self.placeholderARGB = placeholderARGB
		self.textARGB = textARGB
		self.subtextARGB = subtextARGB
		self.mediaData = mediaData
		self.type = type
	}
}

public struct ReceivedRequestPaymentContent: Equatable, Sendable {
	public let note: ReceivedMessageContent?
	public let currencyCodeISO4217: String?
	public let amount1000: UInt64?
	public let requestFrom: String?
	public let expiryTimestamp: Int64?
	public let amount: ReceivedMoneyContent?
	public let background: ReceivedPaymentBackgroundContent?

	public init(
		note: ReceivedMessageContent?,
		currencyCodeISO4217: String?,
		amount1000: UInt64?,
		requestFrom: String?,
		expiryTimestamp: Int64?,
		amount: ReceivedMoneyContent?,
		background: ReceivedPaymentBackgroundContent?
	) {
		self.note = note
		self.currencyCodeISO4217 = currencyCodeISO4217
		self.amount1000 = amount1000
		self.requestFrom = requestFrom
		self.expiryTimestamp = expiryTimestamp
		self.amount = amount
		self.background = background
	}
}

public struct ReceivedSendPaymentContent: Equatable, Sendable {
	public let note: ReceivedMessageContent?
	public let requestMessageKey: ReceivedMessageKey?
	public let background: ReceivedPaymentBackgroundContent?
	public let transactionData: String?

	public init(
		note: ReceivedMessageContent?,
		requestMessageKey: ReceivedMessageKey?,
		background: ReceivedPaymentBackgroundContent?,
		transactionData: String?
	) {
		self.note = note
		self.requestMessageKey = requestMessageKey
		self.background = background
		self.transactionData = transactionData
	}
}

public struct ReceivedPaymentRequestActionContent: Equatable, Sendable {
	public let key: ReceivedMessageKey?

	public init(key: ReceivedMessageKey?) {
		self.key = key
	}
}
