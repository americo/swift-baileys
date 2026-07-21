import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward call and chat messages")
struct WhatsAppClientForwardCallChatMessageTests {
	@Test("forwards received call chat and business call messages through the encrypted send path")
	func forwardsReceivedCallChatAndBusinessCallMessagesThroughEncryptedSendPath() async throws {
		let callMessage = try await forwardedMessage(content: .call(ReceivedCallContent(
			callKey: Data([0x01]),
			conversionSource: "ad",
			conversionData: Data([0x02]),
			conversionDelaySeconds: 9,
			ctwaSignals: "signals",
			ctwaPayload: Data([0x03]),
			nativeFlowCallButtonPayload: "native-flow",
			deeplinkPayload: "deeplink"
		)))

		#expect(callMessage.hasCall)
		#expect(callMessage.call.callKey == Data([0x01]))
		#expect(callMessage.call.conversionSource == "ad")
		#expect(callMessage.call.contextInfo.isForwarded)

		let chatMessage = try await forwardedMessage(content: .chat(ReceivedChatContent(
			displayName: "Support",
			id: "support-chat"
		)))

		#expect(chatMessage.hasChat)
		#expect(chatMessage.chat.displayName == "Support")
		#expect(chatMessage.chat.id == "support-chat")

		let businessCallMessage = try await forwardedMessage(content: .businessCall(ReceivedBusinessCallContent(
			sessionID: "session-1",
			mediaType: .audio,
			masterKey: Data([0x04, 0x05]),
			caption: "Call us"
		)))

		#expect(businessCallMessage.hasBcallMessage)
		#expect(businessCallMessage.bcallMessage.sessionID == "session-1")
		#expect(businessCallMessage.bcallMessage.mediaType == .audio)
		#expect(businessCallMessage.bcallMessage.masterKey == Data([0x04, 0x05]))
		#expect(businessCallMessage.bcallMessage.caption == "Call us")
	}

	private func forwardedMessage(content: ReceivedMessageContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x29]))],
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
				id: "CALLCHAT1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDEDCALLCHAT"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
