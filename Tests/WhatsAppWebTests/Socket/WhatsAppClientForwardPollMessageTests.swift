import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward poll messages")
struct WhatsAppClientForwardPollMessageTests {
	@Test("forwards received poll creation messages through the encrypted send path")
	func forwardsReceivedPollCreationMessagesThroughEncryptedSendPath() async throws {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x1d]))],
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
				id: "POLL1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .pollCreation(ReceivedPollCreationContent(
					name: "Best Baileys port?",
					options: [
						ReceivedPollOption(name: "Swift", hash: "hash-swift"),
						ReceivedPollOption(name: "TypeScript", hash: "hash-typescript")
					],
					selectableOptionsCount: 1,
					encryptedKey: Data([0x01, 0x02, 0x03]),
					contentType: .text,
					pollType: .quiz,
					correctAnswer: ReceivedPollOption(name: "Swift", hash: "hash-swift")
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDPOLL"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.hasPollCreationMessageV3)
		#expect(message.pollCreationMessageV3.name == "Best Baileys port?")
		#expect(message.pollCreationMessageV3.options.map { $0.optionName } == ["Swift", "TypeScript"])
		#expect(message.pollCreationMessageV3.options.map { $0.optionHash } == ["hash-swift", "hash-typescript"])
		#expect(message.pollCreationMessageV3.selectableOptionsCount == 1)
		#expect(message.pollCreationMessageV3.encKey == Data([0x01, 0x02, 0x03]))
		#expect(message.pollCreationMessageV3.pollContentType == .text)
		#expect(message.pollCreationMessageV3.pollType == .quiz)
		#expect(message.pollCreationMessageV3.correctAnswer.optionName == "Swift")
		#expect(message.pollCreationMessageV3.contextInfo.isForwarded)
		#expect(message.pollCreationMessageV3.contextInfo.forwardingScore == 1)
	}
}
