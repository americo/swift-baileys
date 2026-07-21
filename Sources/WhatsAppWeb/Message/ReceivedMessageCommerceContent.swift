import Foundation

public enum ReceivedOrderStatus: Equatable, Sendable {
	case unknown
	case inquiry
	case accepted
	case declined
	case unrecognized(Int)
}

public enum ReceivedOrderSurface: Equatable, Sendable {
	case unknown
	case catalog
	case unrecognized(Int)
}

public struct ReceivedOrderContent: Equatable, Sendable {
	public let orderID: String?
	public let thumbnail: Data?
	public let itemCount: Int32?
	public let status: ReceivedOrderStatus?
	public let surface: ReceivedOrderSurface?
	public let message: String?
	public let orderTitle: String?
	public let sellerJID: String?
	public let token: String?
	public let totalAmount1000: Int64?
	public let totalCurrencyCode: String?
	public let messageVersion: Int32?
	public let orderRequestMessageID: ReceivedMessageKey?
	public let catalogType: String?

	public init(
		orderID: String?,
		thumbnail: Data?,
		itemCount: Int32?,
		status: ReceivedOrderStatus?,
		surface: ReceivedOrderSurface?,
		message: String?,
		orderTitle: String?,
		sellerJID: String?,
		token: String?,
		totalAmount1000: Int64?,
		totalCurrencyCode: String?,
		messageVersion: Int32?,
		orderRequestMessageID: ReceivedMessageKey?,
		catalogType: String?
	) {
		self.orderID = orderID
		self.thumbnail = thumbnail
		self.itemCount = itemCount
		self.status = status
		self.surface = surface
		self.message = message
		self.orderTitle = orderTitle
		self.sellerJID = sellerJID
		self.token = token
		self.totalAmount1000 = totalAmount1000
		self.totalCurrencyCode = totalCurrencyCode
		self.messageVersion = messageVersion
		self.orderRequestMessageID = orderRequestMessageID
		self.catalogType = catalogType
	}
}

public struct ReceivedProductImageContent: Equatable, Sendable {
	public let url: String
	public let directPath: String
	public let mediaKey: Data
	public let fileEncSHA256: Data
	public let fileSHA256: Data
	public let fileLength: UInt64
	public let mediaKeyTimestamp: Int64
	public let mimetype: String
	public let caption: String?
	public let jpegThumbnail: Data?

	public init(
		url: String,
		directPath: String,
		mediaKey: Data,
		fileEncSHA256: Data,
		fileSHA256: Data,
		fileLength: UInt64,
		mediaKeyTimestamp: Int64,
		mimetype: String,
		caption: String?,
		jpegThumbnail: Data?
	) {
		self.url = url
		self.directPath = directPath
		self.mediaKey = mediaKey
		self.fileEncSHA256 = fileEncSHA256
		self.fileSHA256 = fileSHA256
		self.fileLength = fileLength
		self.mediaKeyTimestamp = mediaKeyTimestamp
		self.mimetype = mimetype
		self.caption = caption
		self.jpegThumbnail = jpegThumbnail
	}
}

public struct ReceivedProductSnapshotContent: Equatable, Sendable {
	public let image: ReceivedProductImageContent?
	public let productID: String?
	public let title: String?
	public let description: String?
	public let currencyCode: String?
	public let priceAmount1000: Int64?
	public let retailerID: String?
	public let url: String?
	public let productImageCount: UInt32?
	public let firstImageID: String?
	public let salePriceAmount1000: Int64?
	public let signedURL: String?

	public init(
		image: ReceivedProductImageContent?,
		productID: String?,
		title: String?,
		description: String?,
		currencyCode: String?,
		priceAmount1000: Int64?,
		retailerID: String?,
		url: String?,
		productImageCount: UInt32?,
		firstImageID: String?,
		salePriceAmount1000: Int64?,
		signedURL: String?
	) {
		self.image = image
		self.productID = productID
		self.title = title
		self.description = description
		self.currencyCode = currencyCode
		self.priceAmount1000 = priceAmount1000
		self.retailerID = retailerID
		self.url = url
		self.productImageCount = productImageCount
		self.firstImageID = firstImageID
		self.salePriceAmount1000 = salePriceAmount1000
		self.signedURL = signedURL
	}
}

public struct ReceivedProductCatalogContent: Equatable, Sendable {
	public let image: ReceivedProductImageContent?
	public let title: String?
	public let description: String?

	public init(image: ReceivedProductImageContent?, title: String?, description: String?) {
		self.image = image
		self.title = title
		self.description = description
	}
}

public struct ReceivedProductContent: Equatable, Sendable {
	public let product: ReceivedProductSnapshotContent?
	public let businessOwnerJID: String?
	public let catalog: ReceivedProductCatalogContent?
	public let body: String?
	public let footer: String?

	public init(
		product: ReceivedProductSnapshotContent?,
		businessOwnerJID: String?,
		catalog: ReceivedProductCatalogContent?,
		body: String?,
		footer: String?
	) {
		self.product = product
		self.businessOwnerJID = businessOwnerJID
		self.catalog = catalog
		self.body = body
		self.footer = footer
	}
}
