import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward scheduled call messages")
struct WhatsAppClientForwardScheduledCallMessageTests {
	@Test("forwards received scheduled call creation messages through the encrypted send path")
	func forwardsReceivedScheduledCallCreationMessagesThroughEncryptedSendPath() async throws {
		let message = try await forwardedMessage(
			content: .scheduledCallCreation(ReceivedScheduledCallCreationContent(
				scheduledTimestampMilliseconds: 1_700_200_000_000,
				callType: .video,
				title: "Weekly sync"
			)),
			messageID: "3EB0FORWARDEDSCHEDULEDCALLCREATE"
		)

		#expect(message.hasScheduledCallCreationMessage)
		#expect(message.scheduledCallCreationMessage.scheduledTimestampMs == 1_700_200_000_000)
		#expect(message.scheduledCallCreationMessage.callType == .video)
		#expect(message.scheduledCallCreationMessage.title == "Weekly sync")
	}

	@Test("forwards received scheduled call edit messages through the encrypted send path")
	func forwardsReceivedScheduledCallEditMessagesThroughEncryptedSendPath() async throws {
		let message = try await forwardedMessage(
			content: .scheduledCallEdit(ReceivedScheduledCallEditContent(
				key: ReceivedMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "SCHEDULED_CALL_MESSAGE_ID",
					participant: "258840000000@s.whatsapp.net"
				),
				editType: .cancel
			)),
			messageID: "3EB0FORWARDEDSCHEDULEDCALLCANCEL"
		)

		#expect(message.hasScheduledCallEditMessage)
		#expect(message.scheduledCallEditMessage.key.remoteJid == "120363000000000000@g.us")
		#expect(!message.scheduledCallEditMessage.key.fromMe)
		#expect(message.scheduledCallEditMessage.key.id == "SCHEDULED_CALL_MESSAGE_ID")
		#expect(message.scheduledCallEditMessage.key.participant == "258840000000@s.whatsapp.net")
		#expect(message.scheduledCallEditMessage.editType == .cancel)
	}

	private func forwardedMessage(
		content: ReceivedMessageContent,
		messageID: String
	) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x22]))],
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
				id: "SCHEDULEDCALL1",
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
