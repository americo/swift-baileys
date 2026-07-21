extension ReceivedMessageContentParser {
	static func listContent(_ list: Proto_Message.ListMessage) -> ReceivedListContent {
		ReceivedListContent(
			title: list.hasTitle ? list.title : nil,
			description: list.hasDescription_p ? list.description_p : nil,
			buttonText: list.hasButtonText ? list.buttonText : nil,
			listType: list.hasListType ? listType(list.listType) : nil,
			sections: list.sections.map(listSection),
			productListInfo: list.hasProductListInfo ? productListInfo(list.productListInfo) : nil,
			footerText: list.hasFooterText ? list.footerText : nil
		)
	}

	static func listType(_ type: Proto_Message.ListMessage.ListType) -> ReceivedListType {
		switch type {
		case .unknown:
			.unknown
		case .singleSelect:
			.singleSelect
		case .productList:
			.productList
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	static func listSection(_ section: Proto_Message.ListMessage.Section) -> ReceivedListSectionContent {
		ReceivedListSectionContent(
			title: section.hasTitle ? section.title : nil,
			rows: section.rows.map(listRow)
		)
	}

	static func listRow(_ row: Proto_Message.ListMessage.Row) -> ReceivedListRowContent {
		ReceivedListRowContent(
			title: row.hasTitle ? row.title : nil,
			description: row.hasDescription_p ? row.description_p : nil,
			rowID: row.hasRowID ? row.rowID : nil
		)
	}

	static func productListInfo(_ info: Proto_Message.ListMessage.ProductListInfo) -> ReceivedProductListInfoContent {
		ReceivedProductListInfoContent(
			productSections: info.productSections.map(productListSection),
			headerImage: info.hasHeaderImage ? productListHeaderImage(info.headerImage) : nil,
			businessOwnerJID: info.hasBusinessOwnerJid ? info.businessOwnerJid : nil
		)
	}

	static func productListSection(
		_ section: Proto_Message.ListMessage.ProductSection
	) -> ReceivedProductListSectionContent {
		ReceivedProductListSectionContent(
			title: section.hasTitle ? section.title : nil,
			products: section.products.map {
				ReceivedListProductContent(productID: $0.hasProductID ? $0.productID : nil)
			}
		)
	}

	static func productListHeaderImage(
		_ image: Proto_Message.ListMessage.ProductListHeaderImage
	) -> ReceivedProductListHeaderImageContent {
		ReceivedProductListHeaderImageContent(
			productID: image.hasProductID ? image.productID : nil,
			jpegThumbnail: image.hasJpegThumbnail ? image.jpegThumbnail : nil
		)
	}
}
