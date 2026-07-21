import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward product messages")
struct WhatsAppClientForwardProductMessageTests {
	@Test("forwards received product messages through the encrypted send path")
	func forwardsReceivedProductMessagesThroughEncryptedSendPath() async throws {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x20]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "PRODUCT1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .product(ReceivedProductContent(
					product: ReceivedProductSnapshotContent(
						image: productImage(path: "/product.enc"),
						productID: "PROD-123",
						title: "Swift Baileys mug",
						description: "Ceramic mug",
						currencyCode: "MZN",
						priceAmount1000: 349_000,
						retailerID: "SKU-123",
						url: "https://shop.example/products/123",
						productImageCount: 2,
						firstImageID: "image-1",
						salePriceAmount1000: 299_000,
						signedURL: "https://shop.example/signed/123"
					),
					businessOwnerJID: "258840000100@s.whatsapp.net",
					catalog: ReceivedProductCatalogContent(
						image: productImage(path: "/catalog.enc"),
						title: "Swift Store",
						description: "Developer goods"
					),
					body: "Product details",
					footer: "Catalog footer"
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDPRODUCT"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.hasProductMessage)
		#expect(message.productMessage.product.productID == "PROD-123")
		#expect(message.productMessage.product.title == "Swift Baileys mug")
		#expect(message.productMessage.product.currencyCode == "MZN")
		#expect(message.productMessage.product.priceAmount1000 == 349_000)
		#expect(message.productMessage.product.productImage.directPath == "/product.enc")
		#expect(message.productMessage.product.productImage.mediaKey == Data([0x01, 0x02]))
		#expect(message.productMessage.product.productImage.jpegThumbnail == Data([0x07]))
		#expect(message.productMessage.businessOwnerJid == "258840000100@s.whatsapp.net")
		#expect(message.productMessage.catalog.title == "Swift Store")
		#expect(message.productMessage.catalog.catalogImage.directPath == "/catalog.enc")
		#expect(message.productMessage.body == "Product details")
		#expect(message.productMessage.footer == "Catalog footer")
		#expect(message.productMessage.contextInfo.isForwarded)
		#expect(message.productMessage.contextInfo.forwardingScore == 1)
	}

	private func productImage(path: String) -> ReceivedProductImageContent {
		ReceivedProductImageContent(
			url: "https://mmg.whatsapp.net\(path)",
			directPath: path,
			mediaKey: Data([0x01, 0x02]),
			fileEncSHA256: Data([0x03]),
			fileSHA256: Data([0x04]),
			fileLength: 512,
			mediaKeyTimestamp: 1_700_000_000,
			mimetype: "image/jpeg",
			caption: "caption",
			jpegThumbnail: Data([0x07])
		)
	}
}
