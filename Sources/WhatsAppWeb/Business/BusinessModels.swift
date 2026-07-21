public struct BusinessHoursConfig: Equatable, Sendable {
	public let dayOfWeek: String
	public let mode: String
	public let openTime: Int?
	public let closeTime: Int?

	public init(dayOfWeek: String, mode: String, openTime: Int? = nil, closeTime: Int? = nil) {
		self.dayOfWeek = dayOfWeek
		self.mode = mode
		self.openTime = openTime
		self.closeTime = closeTime
	}
}

public struct BusinessHours: Equatable, Sendable {
	public let timezone: String?
	public let config: [BusinessHoursConfig]

	public init(timezone: String?, config: [BusinessHoursConfig]) {
		self.timezone = timezone
		self.config = config
	}
}

public struct BusinessProfile: Equatable, Sendable {
	public let wid: String?
	public let address: String?
	public let description: String
	public let website: [String]
	public let email: String?
	public let category: String?
	public let businessHours: BusinessHours

	public init(
		wid: String?,
		address: String?,
		description: String,
		website: [String],
		email: String?,
		category: String?,
		businessHours: BusinessHours
	) {
		self.wid = wid
		self.address = address
		self.description = description
		self.website = website
		self.email = email
		self.category = category
		self.businessHours = businessHours
	}
}

public enum BusinessProfileDayOfWeek: String, Sendable {
	case sun
	case mon
	case tue
	case wed
	case thu
	case fri
	case sat
}

public enum BusinessProfileHoursMode: String, Sendable {
	case specificHours = "specific_hours"
	case open24h = "open_24h"
	case appointmentOnly = "appointment_only"
}

public struct BusinessProfileHoursDay: Equatable, Sendable {
	public let day: BusinessProfileDayOfWeek
	public let mode: BusinessProfileHoursMode
	public let openTimeInMinutes: Int?
	public let closeTimeInMinutes: Int?

	public init(
		day: BusinessProfileDayOfWeek,
		mode: BusinessProfileHoursMode,
		openTimeInMinutes: Int? = nil,
		closeTimeInMinutes: Int? = nil
	) {
		self.day = day
		self.mode = mode
		self.openTimeInMinutes = openTimeInMinutes
		self.closeTimeInMinutes = closeTimeInMinutes
	}
}

public struct BusinessProfileHoursUpdate: Equatable, Sendable {
	public let timezone: String
	public let days: [BusinessProfileHoursDay]

	public init(timezone: String, days: [BusinessProfileHoursDay]) {
		self.timezone = timezone
		self.days = days
	}
}

public struct BusinessProfileUpdate: Equatable, Sendable {
	public let address: String?
	public let websites: [String]?
	public let email: String?
	public let description: String?
	public let hours: BusinessProfileHoursUpdate?

	public init(
		address: String? = nil,
		websites: [String]? = nil,
		email: String? = nil,
		description: String? = nil,
		hours: BusinessProfileHoursUpdate? = nil
	) {
		self.address = address
		self.websites = websites
		self.email = email
		self.description = description
		self.hours = hours
	}
}

public struct BusinessCatalog: Equatable, Sendable {
	public let products: [BusinessProduct]
	public let nextPageCursor: String?

	public init(products: [BusinessProduct], nextPageCursor: String?) {
		self.products = products
		self.nextPageCursor = nextPageCursor
	}
}

public struct BusinessProductImageURLs: Equatable, Sendable {
	public let requested: String
	public let original: String

	public init(requested: String, original: String) {
		self.requested = requested
		self.original = original
	}
}

public struct BusinessProduct: Equatable, Sendable {
	public let id: String
	public let name: String
	public let retailerID: String?
	public let url: String?
	public let description: String
	public let price: Int
	public let currency: String
	public let isHidden: Bool
	public let imageURLs: BusinessProductImageURLs
	public let reviewStatus: [String: String]
	public let availability: String

	public init(
		id: String,
		name: String,
		retailerID: String?,
		url: String?,
		description: String,
		price: Int,
		currency: String,
		isHidden: Bool,
		imageURLs: BusinessProductImageURLs,
		reviewStatus: [String: String],
		availability: String
	) {
		self.id = id
		self.name = name
		self.retailerID = retailerID
		self.url = url
		self.description = description
		self.price = price
		self.currency = currency
		self.isHidden = isHidden
		self.imageURLs = imageURLs
		self.reviewStatus = reviewStatus
		self.availability = availability
	}
}

public struct BusinessProductCreate: Equatable, Sendable {
	public let name: String
	public let retailerID: String?
	public let description: String
	public let price: Int
	public let currency: String
	public let isHidden: Bool
	public let originCountryCode: String?
	public let imageURLs: [String]

	public init(
		name: String,
		retailerID: String? = nil,
		description: String,
		price: Int,
		currency: String,
		isHidden: Bool = false,
		originCountryCode: String? = nil,
		imageURLs: [String]
	) {
		self.name = name
		self.retailerID = retailerID
		self.description = description
		self.price = price
		self.currency = currency
		self.isHidden = isHidden
		self.originCountryCode = originCountryCode
		self.imageURLs = imageURLs
	}
}

public struct BusinessProductUpdate: Equatable, Sendable {
	public let name: String?
	public let retailerID: String?
	public let description: String?
	public let price: Int?
	public let currency: String?
	public let isHidden: Bool?
	public let imageURLs: [String]

	public init(
		name: String? = nil,
		retailerID: String? = nil,
		description: String? = nil,
		price: Int? = nil,
		currency: String? = nil,
		isHidden: Bool? = nil,
		imageURLs: [String] = []
	) {
		self.name = name
		self.retailerID = retailerID
		self.description = description
		self.price = price
		self.currency = currency
		self.isHidden = isHidden
		self.imageURLs = imageURLs
	}
}

public struct BusinessCatalogStatus: Equatable, Sendable {
	public let status: String
	public let canAppeal: Bool

	public init(status: String, canAppeal: Bool) {
		self.status = status
		self.canAppeal = canAppeal
	}
}

public struct BusinessCatalogCollection: Equatable, Sendable {
	public let id: String
	public let name: String
	public let products: [BusinessProduct]
	public let status: BusinessCatalogStatus

	public init(id: String, name: String, products: [BusinessProduct], status: BusinessCatalogStatus) {
		self.id = id
		self.name = name
		self.products = products
		self.status = status
	}
}

public struct BusinessCatalogCollections: Equatable, Sendable {
	public let collections: [BusinessCatalogCollection]

	public init(collections: [BusinessCatalogCollection]) {
		self.collections = collections
	}
}

public struct BusinessOrderPrice: Equatable, Sendable {
	public let currency: String
	public let total: Int

	public init(currency: String, total: Int) {
		self.currency = currency
		self.total = total
	}
}

public struct BusinessOrderProduct: Equatable, Sendable {
	public let id: String
	public let imageURL: String
	public let name: String
	public let quantity: Int
	public let currency: String
	public let price: Int

	public init(id: String, imageURL: String, name: String, quantity: Int, currency: String, price: Int) {
		self.id = id
		self.imageURL = imageURL
		self.name = name
		self.quantity = quantity
		self.currency = currency
		self.price = price
	}
}

public struct BusinessOrderDetails: Equatable, Sendable {
	public let price: BusinessOrderPrice
	public let products: [BusinessOrderProduct]

	public init(price: BusinessOrderPrice, products: [BusinessOrderProduct]) {
		self.price = price
		self.products = products
	}
}

public struct BusinessProductDeleteResult: Equatable, Sendable {
	public let deleted: Int

	public init(deleted: Int) {
		self.deleted = deleted
	}
}
