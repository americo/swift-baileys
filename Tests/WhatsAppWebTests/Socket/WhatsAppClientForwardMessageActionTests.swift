import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward message actions")
struct WhatsAppClientForwardMessageActionTests {
	@Test("forwards received pin and keep messages through the encrypted send path")
	func forwardsReceivedPinAndKeepMessagesThroughEncryptedSendPath() async throws {
		let pinMessage = try await forwardedMessage(
			content: .messagePin(ReceivedMessagePinContent(
				key: ReceivedMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "PIN_TARGET",
					participant: "258840000000@s.whatsapp.net"
				),
				action: .pinForAll,
				senderTimestampMilliseconds: 1_700_333_444_000
			)),
			messageID: "3EB0FORWARDEDPIN"
		)

		#expect(pinMessage.hasPinInChatMessage)
		#expect(pinMessage.pinInChatMessage.key.remoteJid == "120363000000000000@g.us")
		#expect(!pinMessage.pinInChatMessage.key.fromMe)
		#expect(pinMessage.pinInChatMessage.key.id == "PIN_TARGET")
		#expect(pinMessage.pinInChatMessage.key.participant == "258840000000@s.whatsapp.net")
		#expect(pinMessage.pinInChatMessage.type == .pinForAll)
		#expect(pinMessage.pinInChatMessage.senderTimestampMs == 1_700_333_444_000)

		let keepMessage = try await forwardedMessage(
			content: .messageKeep(ReceivedMessageKeepContent(
				key: ReceivedMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "KEEP_TARGET",
					participant: "258840000000@s.whatsapp.net"
				),
				action: .undoKeepForAll,
				timestampMilliseconds: 1_700_444_555_000
			)),
			messageID: "3EB0FORWARDEDKEEP"
		)

		#expect(keepMessage.hasKeepInChatMessage)
		#expect(keepMessage.keepInChatMessage.key.remoteJid == "120363000000000000@g.us")
		#expect(!keepMessage.keepInChatMessage.key.fromMe)
		#expect(keepMessage.keepInChatMessage.key.id == "KEEP_TARGET")
		#expect(keepMessage.keepInChatMessage.key.participant == "258840000000@s.whatsapp.net")
		#expect(keepMessage.keepInChatMessage.keepType == .undoKeepForAll)
		#expect(keepMessage.keepInChatMessage.timestampMs == 1_700_444_555_000)
	}

	private func forwardedMessage(
		content: ReceivedMessageContent,
		messageID: String
	) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x24]))],
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
				id: "MESSAGEACTION1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: messageID
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
