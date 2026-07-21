import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward album messages")
struct WhatsAppClientForwardAlbumMessageTests {
	@Test("forwards received album messages through the encrypted send path")
	func forwardsReceivedAlbumMessagesThroughEncryptedSendPath() async throws {
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
				id: "ALBUM1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .album(ReceivedAlbumContent(expectedImageCount: 3, expectedVideoCount: 2)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDALBUM"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.hasAlbumMessage)
		#expect(message.albumMessage.expectedImageCount == 3)
		#expect(message.albumMessage.expectedVideoCount == 2)
		#expect(message.albumMessage.contextInfo.isForwarded)
		#expect(message.albumMessage.contextInfo.forwardingScore == 1)
	}
}
