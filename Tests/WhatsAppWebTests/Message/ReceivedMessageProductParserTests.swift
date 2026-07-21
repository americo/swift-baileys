import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message product parser")
struct ReceivedMessageProductParserTests {
	@Test("parses product messages")
	func parsesProductMessages() throws {
		var productImage = Proto_Message.ImageMessage()
		productImage.url = "https://mmg.whatsapp.net/product.enc"
		productImage.directPath = "/v/t62.7118-24/product"
		productImage.mediaKey = Data([0x01, 0x02, 0x03])
		productImage.fileEncSha256 = Data([0x04, 0x05, 0x06])
		productImage.fileSha256 = Data([0x07, 0x08, 0x09])
		productImage.fileLength = 12_345
		productImage.mediaKeyTimestamp = 1_717_000_000
		productImage.mimetype = "image/jpeg"
		productImage.caption = "Product hero"
		productImage.jpegThumbnail = Data([0x0a, 0x0b])
		var product = Proto_Message.ProductMessage.ProductSnapshot()
		product.productImage = productImage
		product.productID = "product-123"
		product.title = "Running shoes"
		product.description_p = "Lightweight shoes"
		product.currencyCode = "MZN"
		product.priceAmount1000 = 15_990_000
		product.retailerID = "sku-123"
		product.url = "https://shop.example/products/product-123"
		product.productImageCount = 3
		product.firstImageID = "image-1"
		product.salePriceAmount1000 = 12_990_000
		product.signedURL = "https://shop.example/signed/product-123"
		var catalogImage = Proto_Message.ImageMessage()
		catalogImage.url = "https://mmg.whatsapp.net/catalog.enc"
		catalogImage.directPath = "/v/t62.7118-24/catalog"
		catalogImage.mediaKey = Data([0x0c, 0x0d, 0x0e])
		catalogImage.fileEncSha256 = Data([0x0f, 0x10, 0x11])
		catalogImage.fileSha256 = Data([0x12, 0x13, 0x14])
		catalogImage.fileLength = 54_321
		catalogImage.mediaKeyTimestamp = 1_717_000_001
		catalogImage.mimetype = "image/jpeg"
		var catalog = Proto_Message.ProductMessage.CatalogSnapshot()
		catalog.catalogImage = catalogImage
		catalog.title = "Spring catalog"
		catalog.description_p = "Seasonal products"
		var productMessage = Proto_Message.ProductMessage()
		productMessage.product = product
		productMessage.businessOwnerJid = "258840000100@s.whatsapp.net"
		productMessage.catalog = catalog
		productMessage.body = "Available now"
		productMessage.footer = "Tap to view"
		var message = Proto_Message()
		message.productMessage = productMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .product(ReceivedProductContent(
			product: ReceivedProductSnapshotContent(
				image: ReceivedProductImageContent(
					url: "https://mmg.whatsapp.net/product.enc",
					directPath: "/v/t62.7118-24/product",
					mediaKey: Data([0x01, 0x02, 0x03]),
					fileEncSHA256: Data([0x04, 0x05, 0x06]),
					fileSHA256: Data([0x07, 0x08, 0x09]),
					fileLength: 12_345,
					mediaKeyTimestamp: 1_717_000_000,
					mimetype: "image/jpeg",
					caption: "Product hero",
					jpegThumbnail: Data([0x0a, 0x0b])
				),
				productID: "product-123",
				title: "Running shoes",
				description: "Lightweight shoes",
				currencyCode: "MZN",
				priceAmount1000: 15_990_000,
				retailerID: "sku-123",
				url: "https://shop.example/products/product-123",
				productImageCount: 3,
				firstImageID: "image-1",
				salePriceAmount1000: 12_990_000,
				signedURL: "https://shop.example/signed/product-123"
			),
			businessOwnerJID: "258840000100@s.whatsapp.net",
			catalog: ReceivedProductCatalogContent(
				image: ReceivedProductImageContent(
					url: "https://mmg.whatsapp.net/catalog.enc",
					directPath: "/v/t62.7118-24/catalog",
					mediaKey: Data([0x0c, 0x0d, 0x0e]),
					fileEncSHA256: Data([0x0f, 0x10, 0x11]),
					fileSHA256: Data([0x12, 0x13, 0x14]),
					fileLength: 54_321,
					mediaKeyTimestamp: 1_717_000_001,
					mimetype: "image/jpeg",
					caption: nil,
					jpegThumbnail: nil
				),
				title: "Spring catalog",
				description: "Seasonal products"
			),
			body: "Available now",
			footer: "Tap to view"
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent optional product fields")
	func preservesAbsentOptionalProductFields() throws {
		var productMessage = Proto_Message.ProductMessage()
		productMessage.body = "Only body"
		var message = Proto_Message()
		message.productMessage = productMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .product(ReceivedProductContent(
			product: nil,
			businessOwnerJID: nil,
			catalog: nil,
			body: "Only body",
			footer: nil
		)))
	}
}
