import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward interactive response messages")
struct WhatsAppClientForwardInteractiveResponseMessageTests {
	@Test("forwards received buttons response messages through the encrypted send path")
	func forwardsReceivedButtonsResponseMessagesThroughEncryptedSendPath() async throws {
		let message = try await forwardedPayload(for: .buttonsResponse(ReceivedButtonsResponseContent(
			selectedButtonID: "confirm",
			selectedDisplayText: "Confirm",
			type: .displayText
		)))

		#expect(message.hasButtonsResponseMessage)
		#expect(message.buttonsResponseMessage.selectedButtonID == "confirm")
		#expect(message.buttonsResponseMessage.selectedDisplayText == "Confirm")
		#expect(message.buttonsResponseMessage.type == .displayText)
		#expect(message.buttonsResponseMessage.contextInfo.isForwarded)
		#expect(message.buttonsResponseMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards received list response messages through the encrypted send path")
	func forwardsReceivedListResponseMessagesThroughEncryptedSendPath() async throws {
		let message = try await forwardedPayload(for: .listResponse(ReceivedListResponseContent(
			title: "Delivery",
			listType: .singleSelect,
			selectedRowID: "delivery",
			description: "Send it to my address"
		)))

		#expect(message.hasListResponseMessage)
		#expect(message.listResponseMessage.title == "Delivery")
		#expect(message.listResponseMessage.listType == .singleSelect)
		#expect(message.listResponseMessage.singleSelectReply.selectedRowID == "delivery")
		#expect(message.listResponseMessage.description_p == "Send it to my address")
		#expect(message.listResponseMessage.contextInfo.isForwarded)
		#expect(message.listResponseMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards received template button reply messages through the encrypted send path")
	func forwardsReceivedTemplateButtonReplyMessagesThroughEncryptedSendPath() async throws {
		let message = try await forwardedPayload(for: .templateButtonReply(ReceivedTemplateButtonReplyContent(
			selectedID: "ship_now",
			selectedDisplayText: "Ship now",
			selectedIndex: 2,
			selectedCarouselCardIndex: 4
		)))

		#expect(message.hasTemplateButtonReplyMessage)
		#expect(message.templateButtonReplyMessage.selectedID == "ship_now")
		#expect(message.templateButtonReplyMessage.selectedDisplayText == "Ship now")
		#expect(message.templateButtonReplyMessage.selectedIndex == 2)
		#expect(message.templateButtonReplyMessage.selectedCarouselCardIndex == 4)
		#expect(message.templateButtonReplyMessage.contextInfo.isForwarded)
		#expect(message.templateButtonReplyMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards received native flow response messages through the encrypted send path")
	func forwardsReceivedNativeFlowResponseMessagesThroughEncryptedSendPath() async throws {
		let message = try await forwardedPayload(for: .interactiveResponse(ReceivedInteractiveResponseContent(
			body: ReceivedInteractiveResponseBodyContent(text: "Submitted", format: .extensions1),
			nativeFlowResponse: ReceivedNativeFlowResponseContent(
				name: "single_select",
				paramsJSON: #"{"selected":"delivery"}"#,
				version: 3
			)
		)))

		#expect(message.hasInteractiveResponseMessage)
		#expect(message.interactiveResponseMessage.body.text == "Submitted")
		#expect(message.interactiveResponseMessage.body.format == .extensions1)
		#expect(message.interactiveResponseMessage.nativeFlowResponseMessage.name == "single_select")
		#expect(message.interactiveResponseMessage.nativeFlowResponseMessage.paramsJson == #"{"selected":"delivery"}"#)
		#expect(message.interactiveResponseMessage.nativeFlowResponseMessage.version == 3)
		#expect(message.interactiveResponseMessage.contextInfo.isForwarded)
		#expect(message.interactiveResponseMessage.contextInfo.forwardingScore == 1)
	}

	private func forwardedPayload(for content: ReceivedMessageContent) async throws -> Proto_Message {
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
				id: "RESPONSE1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDEDRESPONSE"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
