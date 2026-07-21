import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message order parser")
struct ReceivedMessageOrderParserTests {
	@Test("parses order messages")
	func parsesOrderMessages() throws {
		let thumbnail = Data([0x07, 0x08, 0x09])
		var requestKey = Proto_MessageKey()
		requestKey.remoteJid = "258840000000@s.whatsapp.net"
		requestKey.fromMe = true
		requestKey.id = "ORDER_REQUEST"
		var order = Proto_Message.OrderMessage()
		order.orderID = "ORDER-123"
		order.thumbnail = thumbnail
		order.itemCount = 3
		order.status = .accepted
		order.surface = .catalog
		order.message = "Please confirm"
		order.orderTitle = "Running shoes"
		order.sellerJid = "258840000100@s.whatsapp.net"
		order.token = "order-token"
		order.totalAmount1000 = 15_990_000
		order.totalCurrencyCode = "MZN"
		order.messageVersion = 2
		order.orderRequestMessageID = requestKey
		order.catalogType = "retail"
		var message = Proto_Message()
		message.orderMessage = order

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .order(ReceivedOrderContent(
			orderID: "ORDER-123",
			thumbnail: thumbnail,
			itemCount: 3,
			status: .accepted,
			surface: .catalog,
			message: "Please confirm",
			orderTitle: "Running shoes",
			sellerJID: "258840000100@s.whatsapp.net",
			token: "order-token",
			totalAmount1000: 15_990_000,
			totalCurrencyCode: "MZN",
			messageVersion: 2,
			orderRequestMessageID: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: true,
				id: "ORDER_REQUEST",
				participant: nil
			),
			catalogType: "retail"
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent optional order fields")
	func preservesAbsentOptionalOrderFields() throws {
		var order = Proto_Message.OrderMessage()
		order.orderID = "ORDER-EMPTY"
		var message = Proto_Message()
		message.orderMessage = order

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .order(ReceivedOrderContent(
			orderID: "ORDER-EMPTY",
			thumbnail: nil,
			itemCount: nil,
			status: nil,
			surface: nil,
			message: nil,
			orderTitle: nil,
			sellerJID: nil,
			token: nil,
			totalAmount1000: nil,
			totalCurrencyCode: nil,
			messageVersion: nil,
			orderRequestMessageID: nil,
			catalogType: nil
		)))
	}
}
