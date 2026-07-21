import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward order messages")
struct WhatsAppClientForwardOrderMessageTests {
	@Test("forwards received order messages through the encrypted send path")
	func forwardsReceivedOrderMessagesThroughEncryptedSendPath() async throws {
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
				id: "ORDER1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .order(ReceivedOrderContent(
					orderID: "ORDER-123",
					thumbnail: Data([0x07, 0x08, 0x09]),
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
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDORDER"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.hasOrderMessage)
		#expect(message.orderMessage.orderID == "ORDER-123")
		#expect(message.orderMessage.thumbnail == Data([0x07, 0x08, 0x09]))
		#expect(message.orderMessage.itemCount == 3)
		#expect(message.orderMessage.status == .accepted)
		#expect(message.orderMessage.surface == .catalog)
		#expect(message.orderMessage.message == "Please confirm")
		#expect(message.orderMessage.orderTitle == "Running shoes")
		#expect(message.orderMessage.sellerJid == "258840000100@s.whatsapp.net")
		#expect(message.orderMessage.token == "order-token")
		#expect(message.orderMessage.totalAmount1000 == 15_990_000)
		#expect(message.orderMessage.totalCurrencyCode == "MZN")
		#expect(message.orderMessage.messageVersion == 2)
		#expect(message.orderMessage.orderRequestMessageID.remoteJid == "258840000000@s.whatsapp.net")
		#expect(message.orderMessage.orderRequestMessageID.fromMe)
		#expect(message.orderMessage.orderRequestMessageID.id == "ORDER_REQUEST")
		#expect(message.orderMessage.catalogType == "retail")
		#expect(message.orderMessage.contextInfo.isForwarded)
		#expect(message.orderMessage.contextInfo.forwardingScore == 1)
	}
}
