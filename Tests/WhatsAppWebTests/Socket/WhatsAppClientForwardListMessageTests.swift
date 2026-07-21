import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward list messages")
struct WhatsAppClientForwardListMessageTests {
	@Test("forwards received list messages through the encrypted send path")
	func forwardsReceivedListMessagesThroughEncryptedSendPath() async throws {
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
				id: "LIST1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .list(ReceivedListContent(
					title: "Choose an option",
					description: "How should we handle this order?",
					buttonText: "Options",
					listType: .productList,
					sections: [
						ReceivedListSectionContent(
							title: "Fulfillment",
							rows: [
								ReceivedListRowContent(
									title: "Delivery",
									description: "Send it to my address",
									rowID: "delivery"
								)
							]
						)
					],
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
					footerText: "Reply with one option"
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDLIST"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.hasListMessage)
		#expect(message.listMessage.title == "Choose an option")
		#expect(message.listMessage.description_p == "How should we handle this order?")
		#expect(message.listMessage.buttonText == "Options")
		#expect(message.listMessage.listType == .productList)
		#expect(message.listMessage.sections[0].title == "Fulfillment")
		#expect(message.listMessage.sections[0].rows[0].rowID == "delivery")
		#expect(message.listMessage.productListInfo.productSections[0].products.map { $0.productID } == [
			"product-1",
			"product-2"
		])
		#expect(message.listMessage.productListInfo.headerImage.jpegThumbnail == Data([0x01, 0x02]))
		#expect(message.listMessage.productListInfo.businessOwnerJid == "258840000100@s.whatsapp.net")
		#expect(message.listMessage.footerText == "Reply with one option")
		#expect(message.listMessage.contextInfo.isForwarded)
		#expect(message.listMessage.contextInfo.forwardingScore == 1)
	}
}
