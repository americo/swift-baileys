import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward call log messages")
struct WhatsAppClientForwardCallLogMessageTests {
	@Test("forwards received call log messages through the encrypted send path")
	func forwardsReceivedCallLogMessagesThroughEncryptedSendPath() async throws {
		let message = try await forwardedMessage(content: .callLog(ReceivedCallLogContent(
			isVideo: true,
			outcome: .missed,
			durationSeconds: 42,
			callType: .voiceChat,
			participants: [
				ReceivedCallLogParticipant(
					jid: "258840000001@s.whatsapp.net",
					outcome: .connected
				),
				ReceivedCallLogParticipant(
					jid: "258840000002@s.whatsapp.net",
					outcome: .rejected
				)
			]
		)))

		#expect(message.hasCallLogMesssage)
		#expect(message.callLogMesssage.isVideo)
		#expect(message.callLogMesssage.callOutcome == .missed)
		#expect(message.callLogMesssage.durationSecs == 42)
		#expect(message.callLogMesssage.callType == .voiceChat)
		#expect(message.callLogMesssage.participants.count == 2)
		#expect(message.callLogMesssage.participants[0].jid == "258840000001@s.whatsapp.net")
		#expect(message.callLogMesssage.participants[0].callOutcome == .connected)
		#expect(message.callLogMesssage.participants[1].jid == "258840000002@s.whatsapp.net")
		#expect(message.callLogMesssage.participants[1].callOutcome == .rejected)
	}

	private func forwardedMessage(content: ReceivedMessageContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x25]))],
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
				id: "CALLLOG1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDEDCALLLOG"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
