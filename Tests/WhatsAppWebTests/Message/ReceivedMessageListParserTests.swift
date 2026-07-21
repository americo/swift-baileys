import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message list parser")
struct ReceivedMessageListParserTests {
	@Test("parses single select list messages")
	func parsesSingleSelectListMessages() throws {
		var firstRow = Proto_Message.ListMessage.Row()
		firstRow.title = "Delivery"
		firstRow.description_p = "Send it to my address"
		firstRow.rowID = "delivery"
		var secondRow = Proto_Message.ListMessage.Row()
		secondRow.title = "Pickup"
		secondRow.rowID = "pickup"
		var section = Proto_Message.ListMessage.Section()
		section.title = "Fulfillment"
		section.rows = [firstRow, secondRow]
		var list = Proto_Message.ListMessage()
		list.title = "Choose an option"
		list.description_p = "How should we handle the order?"
		list.buttonText = "Options"
		list.listType = .singleSelect
		list.sections = [section]
		list.footerText = "Reply with one option"
		var message = Proto_Message()
		message.listMessage = list

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .list(ReceivedListContent(
			title: "Choose an option",
			description: "How should we handle the order?",
			buttonText: "Options",
			listType: .singleSelect,
			sections: [
				ReceivedListSectionContent(
					title: "Fulfillment",
					rows: [
						ReceivedListRowContent(
							title: "Delivery",
							description: "Send it to my address",
							rowID: "delivery"
						),
						ReceivedListRowContent(
							title: "Pickup",
							description: nil,
							rowID: "pickup"
						)
					]
				)
			],
			productListInfo: nil,
			footerText: "Reply with one option"
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses product list message metadata")
	func parsesProductListMessageMetadata() throws {
		var firstProduct = Proto_Message.ListMessage.Product()
		firstProduct.productID = "product-1"
		var secondProduct = Proto_Message.ListMessage.Product()
		secondProduct.productID = "product-2"
		var productSection = Proto_Message.ListMessage.ProductSection()
		productSection.title = "Featured"
		productSection.products = [firstProduct, secondProduct]
		var headerImage = Proto_Message.ListMessage.ProductListHeaderImage()
		headerImage.productID = "product-1"
		headerImage.jpegThumbnail = Data([0x01, 0x02])
		var productListInfo = Proto_Message.ListMessage.ProductListInfo()
		productListInfo.productSections = [productSection]
		productListInfo.headerImage = headerImage
		productListInfo.businessOwnerJid = "258840000100@s.whatsapp.net"
		var list = Proto_Message.ListMessage()
		list.listType = .productList
		list.productListInfo = productListInfo
		var message = Proto_Message()
		message.listMessage = list

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .list(ReceivedListContent(
			title: nil,
			description: nil,
			buttonText: nil,
			listType: .productList,
			sections: [],
			productListInfo: ReceivedProductListInfoContent(
				productSections: [
					ReceivedProductListSectionContent(
						title: "Featured",
						products: [
							ReceivedListProductContent(productID: "product-1"),
							ReceivedListProductContent(productID: "product-2")
						]
					)
				],
				headerImage: ReceivedProductListHeaderImageContent(
					productID: "product-1",
					jpegThumbnail: Data([0x01, 0x02])
				),
				businessOwnerJID: "258840000100@s.whatsapp.net"
			),
			footerText: nil
		)))
	}

	@Test("preserves absent optional list fields")
	func preservesAbsentOptionalListFields() throws {
		var message = Proto_Message()
		message.listMessage = Proto_Message.ListMessage()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .list(ReceivedListContent(
			title: nil,
			description: nil,
			buttonText: nil,
			listType: nil,
			sections: [],
			productListInfo: nil,
			footerText: nil
		)))
	}
}
