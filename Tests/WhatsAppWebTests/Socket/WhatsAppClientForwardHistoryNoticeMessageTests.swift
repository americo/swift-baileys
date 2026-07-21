import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward history notice messages")
struct WhatsAppClientForwardHistoryNoticeMessageTests {
	@Test("forwards received message history notices through the encrypted send path")
	func forwardsReceivedMessageHistoryNoticesThroughEncryptedSendPath() async throws {
		let message = try await forwardedMessage(content: .messageHistoryNotice(
			ReceivedMessageHistoryNoticeContent(metadata: ReceivedMessageHistoryMetadataContent(
				historyReceivers: ["111@s.whatsapp.net", "222@s.whatsapp.net"],
				oldestMessageTimestamp: 1_717_700_000,
				messageCount: 42
			))
		))

		#expect(message.hasMessageHistoryNotice)
		#expect(message.messageHistoryNotice.hasMessageHistoryMetadata)
		#expect(message.messageHistoryNotice.messageHistoryMetadata.historyReceivers == [
			"111@s.whatsapp.net",
			"222@s.whatsapp.net"
		])
		#expect(message.messageHistoryNotice.messageHistoryMetadata.oldestMessageTimestamp == 1_717_700_000)
		#expect(message.messageHistoryNotice.messageHistoryMetadata.messageCount == 42)
	}

	private func forwardedMessage(content: ReceivedMessageContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x26]))],
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
				id: "HISTORYNOTICE1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDEDHISTORYNOTICE"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
