import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward interactive messages")
struct WhatsAppClientForwardInteractiveMessageTests {
	@Test("forwards received native-flow interactive messages through the encrypted send path")
	func forwardsReceivedNativeFlowInteractiveMessagesThroughEncryptedSendPath() async throws {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x21]))],
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
				id: "INTERACTIVE1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .interactive(ReceivedInteractiveContent(
					header: ReceivedInteractiveHeaderContent(
						title: "Choose delivery",
						subtitle: "Order #123",
						hasMediaAttachment: true,
						media: .jpegThumbnail(Data([0x01, 0x02]))
					),
					body: ReceivedInteractiveBodyContent(text: "Select a delivery slot"),
					footer: ReceivedInteractiveFooterContent(
						text: "Tap to continue",
						hasMediaAttachment: nil,
						media: nil
					),
					message: .nativeFlow(ReceivedInteractiveNativeFlowContent(
						buttons: [
							ReceivedInteractiveNativeFlowButtonContent(
								name: "single_select",
								buttonParamsJSON: #"{"screen":"delivery"}"#
							)
						],
						messageParamsJSON: #"{"flow":"checkout"}"#,
						messageVersion: 3
					))
				)),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDINTERACTIVE"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.hasInteractiveMessage)
		#expect(message.interactiveMessage.header.title == "Choose delivery")
		#expect(message.interactiveMessage.header.subtitle == "Order #123")
		#expect(message.interactiveMessage.header.hasMediaAttachment_p)
		guard case .jpegThumbnail(let thumbnail)? = message.interactiveMessage.header.media else {
			Issue.record("expected jpeg thumbnail interactive header")
			return
		}
		#expect(thumbnail == Data([0x01, 0x02]))
		#expect(message.interactiveMessage.body.text == "Select a delivery slot")
		#expect(message.interactiveMessage.footer.text == "Tap to continue")
		guard case .nativeFlowMessage(let nativeFlow)? = message.interactiveMessage.interactiveMessage else {
			Issue.record("expected native-flow interactive message")
			return
		}
		#expect(nativeFlow.buttons.map { $0.name } == ["single_select"])
		#expect(nativeFlow.buttons.map { $0.buttonParamsJson } == [#"{"screen":"delivery"}"#])
		#expect(nativeFlow.messageParamsJson == #"{"flow":"checkout"}"#)
		#expect(nativeFlow.messageVersion == 3)
		#expect(message.interactiveMessage.contextInfo.isForwarded)
		#expect(message.interactiveMessage.contextInfo.forwardingScore == 1)
	}
}
