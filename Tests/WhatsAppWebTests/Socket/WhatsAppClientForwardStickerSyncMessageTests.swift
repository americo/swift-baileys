import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward sticker sync messages")
struct WhatsAppClientForwardStickerSyncMessageTests {
	@Test("forwards received sticker sync rmr messages through the encrypted send path")
	func forwardsReceivedStickerSyncRMRMessagesThroughEncryptedSendPath() async throws {
		let message = try await forwardedMessage(content: .stickerSyncRMR(ReceivedStickerSyncRMRContent(
			filehash: ["hash-a", "hash-b"],
			rmrSource: "rmr-source",
			requestTimestamp: 1_717_171_717
		)))

		#expect(message.hasStickerSyncRmrMessage)
		#expect(message.stickerSyncRmrMessage.filehash == ["hash-a", "hash-b"])
		#expect(message.stickerSyncRmrMessage.rmrSource == "rmr-source")
		#expect(message.stickerSyncRmrMessage.requestTimestamp == 1_717_171_717)
	}

	private func forwardedMessage(content: ReceivedMessageContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x2d]))],
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
				id: "STICKERSYNC1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDSTICKERSYNC"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
