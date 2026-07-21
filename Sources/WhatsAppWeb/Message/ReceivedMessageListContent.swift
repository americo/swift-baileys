import Foundation

public enum ReceivedListType: Equatable, Sendable {
	case unknown
	case singleSelect
	case productList
	case unrecognized(Int)
}

public struct ReceivedListRowContent: Equatable, Sendable {
	public let title: String?
	public let description: String?
	public let rowID: String?

	public init(title: String?, description: String?, rowID: String?) {
		self.title = title
		self.description = description
		self.rowID = rowID
	}
}

public struct ReceivedListSectionContent: Equatable, Sendable {
	public let title: String?
	public let rows: [ReceivedListRowContent]

	public init(title: String?, rows: [ReceivedListRowContent]) {
		self.title = title
		self.rows = rows
	}
}

public struct ReceivedListProductContent: Equatable, Sendable {
	public let productID: String?

	public init(productID: String?) {
		self.productID = productID
	}
}

public struct ReceivedProductListHeaderImageContent: Equatable, Sendable {
	public let productID: String?
	public let jpegThumbnail: Data?

	public init(productID: String?, jpegThumbnail: Data?) {
		self.productID = productID
		self.jpegThumbnail = jpegThumbnail
	}
}

public struct ReceivedProductListSectionContent: Equatable, Sendable {
	public let title: String?
	public let products: [ReceivedListProductContent]

	public init(title: String?, products: [ReceivedListProductContent]) {
		self.title = title
		self.products = products
	}
}

public struct ReceivedProductListInfoContent: Equatable, Sendable {
	public let productSections: [ReceivedProductListSectionContent]
	public let headerImage: ReceivedProductListHeaderImageContent?
	public let businessOwnerJID: String?

	public init(
		productSections: [ReceivedProductListSectionContent],
		headerImage: ReceivedProductListHeaderImageContent?,
		businessOwnerJID: String?
	) {
		self.productSections = productSections
		self.headerImage = headerImage
		self.businessOwnerJID = businessOwnerJID
	}
}

public struct ReceivedListContent: Equatable, Sendable {
	public let title: String?
	public let description: String?
	public let buttonText: String?
	public let listType: ReceivedListType?
	public let sections: [ReceivedListSectionContent]
	public let productListInfo: ReceivedProductListInfoContent?
	public let footerText: String?

	public init(
		title: String?,
		description: String?,
		buttonText: String?,
		listType: ReceivedListType?,
		sections: [ReceivedListSectionContent],
		productListInfo: ReceivedProductListInfoContent?,
		footerText: String?
	) {
		self.title = title
		self.description = description
		self.buttonText = buttonText
		self.listType = listType
		self.sections = sections
		self.productListInfo = productListInfo
		self.footerText = footerText
	}
}
