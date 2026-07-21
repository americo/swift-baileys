import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward reaction messages")
struct WhatsAppClientForwardReactionMessageTests {
	@Test("forwards received reaction messages through the encrypted send path")
	func forwardsReceivedReactionMessagesThroughEncryptedSendPath() async throws {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x23]))],
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
				id: "REACTION1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .reaction(ReceivedReactionContent(
					key: ReceivedMessageKey(
						remoteJID: "123@s.whatsapp.net",
						fromMe: false,
						id: "3EB0TARGET",
						participant: "456@s.whatsapp.net"
					),
					text: "+1",
					groupingKey: "3EB0TARGET",
					senderTimestampMilliseconds: 1_700_000_999_000
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDREACTION"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.hasReactionMessage)
		#expect(message.reactionMessage.key.remoteJid == "123@s.whatsapp.net")
		#expect(!message.reactionMessage.key.fromMe)
		#expect(message.reactionMessage.key.id == "3EB0TARGET")
		#expect(message.reactionMessage.key.participant == "456@s.whatsapp.net")
		#expect(message.reactionMessage.text == "+1")
		#expect(message.reactionMessage.groupingKey == "3EB0TARGET")
		#expect(message.reactionMessage.senderTimestampMs == 1_700_000_999_000)
	}
}
