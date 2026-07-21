import Foundation

enum ForwardListMessageMapper {
	static func message(from content: ReceivedListContent) -> Proto_Message {
		var list = Proto_Message.ListMessage()
		if let title = content.title {
			list.title = title
		}
		if let description = content.description {
			list.description_p = description
		}
		if let buttonText = content.buttonText {
			list.buttonText = buttonText
		}
		if let listType = content.listType {
			list.listType = protoListType(from: listType)
		}
		list.sections = content.sections.map(protoSection)
		if let productListInfo = content.productListInfo {
			list.productListInfo = protoProductListInfo(from: productListInfo)
		}
		if let footerText = content.footerText {
			list.footerText = footerText
		}

		var message = Proto_Message()
		message.listMessage = list
		return message
	}

	private static func protoListType(
		from type: ReceivedListType
	) -> Proto_Message.ListMessage.ListType {
		switch type {
		case .unknown:
			.unknown
		case .singleSelect:
			.singleSelect
		case .productList:
			.productList
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}

	private static func protoSection(
		from content: ReceivedListSectionContent
	) -> Proto_Message.ListMessage.Section {
		var section = Proto_Message.ListMessage.Section()
		if let title = content.title {
			section.title = title
		}
		section.rows = content.rows.map(protoRow)
		return section
	}

	private static func protoRow(from content: ReceivedListRowContent) -> Proto_Message.ListMessage.Row {
		var row = Proto_Message.ListMessage.Row()
		if let title = content.title {
			row.title = title
		}
		if let description = content.description {
			row.description_p = description
		}
		if let rowID = content.rowID {
			row.rowID = rowID
		}
		return row
	}

	private static func protoProductListInfo(
		from content: ReceivedProductListInfoContent
	) -> Proto_Message.ListMessage.ProductListInfo {
		var info = Proto_Message.ListMessage.ProductListInfo()
		info.productSections = content.productSections.map(protoProductSection)
		if let headerImage = content.headerImage {
			info.headerImage = protoProductListHeaderImage(from: headerImage)
		}
		if let businessOwnerJID = content.businessOwnerJID {
			info.businessOwnerJid = businessOwnerJID
		}
		return info
	}

	private static func protoProductSection(
		from content: ReceivedProductListSectionContent
	) -> Proto_Message.ListMessage.ProductSection {
		var section = Proto_Message.ListMessage.ProductSection()
		if let title = content.title {
			section.title = title
		}
		section.products = content.products.map(protoProduct)
		return section
	}

	private static func protoProduct(
		from content: ReceivedListProductContent
	) -> Proto_Message.ListMessage.Product {
		var product = Proto_Message.ListMessage.Product()
		if let productID = content.productID {
			product.productID = productID
		}
		return product
	}

	private static func protoProductListHeaderImage(
		from content: ReceivedProductListHeaderImageContent
	) -> Proto_Message.ListMessage.ProductListHeaderImage {
		var image = Proto_Message.ListMessage.ProductListHeaderImage()
		if let productID = content.productID {
			image.productID = productID
		}
		if let jpegThumbnail = content.jpegThumbnail {
			image.jpegThumbnail = jpegThumbnail
		}
		return image
	}
}
