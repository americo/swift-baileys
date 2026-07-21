import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward AI rich response messages")
struct WhatsAppClientForwardAIRichResponseMessageTests {
	@Test("forwards received AI rich responses through the encrypted send path")
	func forwardsReceivedAIRichResponsesThroughEncryptedSendPath() async throws {
		var submessage = Proto_AIRichResponseSubMessage()
		submessage.messageType = .aiRichResponseText
		submessage.messageText = "Forwarded answer"
		var richResponse = Proto_AIRichResponseMessage()
		richResponse.messageType = .aiRichResponseTypeStandard
		richResponse.submessages = [submessage]

		let message = try await forwardedMessage(content: .aiRichResponse(
			ReceivedAIRichResponseContent(
				messageType: .standard,
				submessages: [ReceivedAIRichResponseSubMessageContent(type: .text, text: "stale text")],
				unifiedResponseData: nil,
				serializedBytes: try richResponse.serializedData()
			)
		))

		#expect(message.hasRichResponseMessage)
		#expect(message.richResponseMessage.messageType == .aiRichResponseTypeStandard)
		#expect(message.richResponseMessage.submessages.count == 1)
		#expect(message.richResponseMessage.submessages[0].messageType == .aiRichResponseText)
		#expect(message.richResponseMessage.submessages[0].messageText == "Forwarded answer")
	}

	@Test("forwards manually constructed AI rich responses")
	func forwardsManuallyConstructedAIRichResponses() async throws {
		let message = try await forwardedMessage(content: .aiRichResponse(
			ReceivedAIRichResponseContent(
				messageType: .standard,
				submessages: [ReceivedAIRichResponseSubMessageContent(type: .text, text: "Manual answer")],
				unifiedResponseData: Data([0x04]),
				serializedBytes: nil
			)
		))

		#expect(message.hasRichResponseMessage)
		#expect(message.richResponseMessage.messageType == .aiRichResponseTypeStandard)
		#expect(message.richResponseMessage.submessages.count == 1)
		#expect(message.richResponseMessage.submessages[0].messageText == "Manual answer")
		#expect(message.richResponseMessage.unifiedResponse.data == Data([0x04]))
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
				id: "AIRICHRESPONSE1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDEDAIRICHRESPONSE"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
