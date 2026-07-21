import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward history bundle messages")
struct WhatsAppClientForwardHistoryBundleMessageTests {
	@Test("forwards received message history bundles through the encrypted send path")
	func forwardsReceivedMessageHistoryBundlesThroughEncryptedSendPath() async throws {
		let message = try await forwardedMessage(content: .messageHistoryBundle(
			ReceivedMessageHistoryBundleContent(
				mimetype: "application/octet-stream",
				fileSHA256: Data([0x01]),
				mediaKey: Data([0x02]),
				fileEncSHA256: Data([0x03]),
				directPath: "/v/t62.7118-24/history-bundle.enc",
				mediaKeyTimestamp: 1_800_000_000,
				metadata: ReceivedMessageHistoryMetadataContent(
					historyReceivers: ["111@s.whatsapp.net", "222@s.whatsapp.net"],
					oldestMessageTimestamp: 1_717_700_000,
					messageCount: 42
				)
			)
		))

		#expect(message.hasMessageHistoryBundle)
		#expect(message.messageHistoryBundle.mimetype == "application/octet-stream")
		#expect(message.messageHistoryBundle.fileSha256 == Data([0x01]))
		#expect(message.messageHistoryBundle.mediaKey == Data([0x02]))
		#expect(message.messageHistoryBundle.fileEncSha256 == Data([0x03]))
		#expect(message.messageHistoryBundle.directPath == "/v/t62.7118-24/history-bundle.enc")
		#expect(message.messageHistoryBundle.mediaKeyTimestamp == 1_800_000_000)
		#expect(message.messageHistoryBundle.hasMessageHistoryMetadata)
		#expect(message.messageHistoryBundle.messageHistoryMetadata.historyReceivers == [
			"111@s.whatsapp.net",
			"222@s.whatsapp.net"
		])
		#expect(message.messageHistoryBundle.messageHistoryMetadata.oldestMessageTimestamp == 1_717_700_000)
		#expect(message.messageHistoryBundle.messageHistoryMetadata.messageCount == 42)
	}

	private func forwardedMessage(content: ReceivedMessageContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x28]))],
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
				id: "HISTORYBUNDLE1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDEDHISTORYBUNDLE"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
