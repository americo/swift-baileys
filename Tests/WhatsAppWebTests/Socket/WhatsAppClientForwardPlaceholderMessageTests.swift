import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward placeholder messages")
struct WhatsAppClientForwardPlaceholderMessageTests {
	@Test("forwards received placeholder messages through the encrypted send path")
	func forwardsReceivedPlaceholderMessagesThroughEncryptedSendPath() async throws {
		let message = try await forwardedMessage(content: .placeholder(ReceivedPlaceholderContent(
			type: .maskLinkedDevices
		)))

		#expect(message.hasPlaceholderMessage)
		#expect(message.placeholderMessage.type == .maskLinkedDevices)
	}

	private func forwardedMessage(content: ReceivedMessageContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x27]))],
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
				id: "PLACEHOLDER1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDEDPLACEHOLDER"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
