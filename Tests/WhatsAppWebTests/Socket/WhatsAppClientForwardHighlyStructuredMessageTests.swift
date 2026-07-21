import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward highly structured messages")
struct WhatsAppClientForwardHighlyStructuredMessageTests {
	@Test("forwards received highly structured messages through the encrypted send path")
	func forwardsReceivedHighlyStructuredMessagesThroughEncryptedSendPath() async throws {
		let message = try await forwardedMessage(content: .highlyStructured(highlyStructuredContent()))

		let hsm = message.highlyStructuredMessage
		#expect(hsm.namespace == "commerce")
		#expect(hsm.elementName == "order_update")
		#expect(hsm.params == ["Alice", "A-123"])
		#expect(hsm.fallbackLg == "en")
		#expect(hsm.fallbackLc == "US")
		#expect(hsm.deterministicLg == "pt")
		#expect(hsm.deterministicLc == "MZ")
		#expect(hsm.localizableParams[0].default == "$12,345.00")
		#expect(hsm.localizableParams[0].currency.currencyCode == "USD")
		#expect(hsm.localizableParams[0].currency.amount1000 == 12_345_000)
		#expect(hsm.localizableParams[1].dateTime.component.dayOfWeek == .friday)
		#expect(hsm.localizableParams[1].dateTime.component.year == 2026)
		#expect(hsm.localizableParams[1].dateTime.component.calendar == .gregorian)
		#expect(hsm.localizableParams[2].dateTime.unixEpoch.timestamp == 1_717_900_000)
	}

	@Test("forwards received comments with highly structured content")
	func forwardsReceivedCommentsWithHighlyStructuredContent() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .highlyStructured(highlyStructuredContent()),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-hsm-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.message.highlyStructuredMessage.elementName == "order_update")
		#expect(message.commentMessage.message.highlyStructuredMessage.localizableParams[0].currency.currencyCode == "USD")
	}

	@Test("forwards received edited messages with highly structured content")
	func forwardsReceivedEditedMessagesWithHighlyStructuredContent() async throws {
		let message = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITEDHSM",
				participant: nil
			),
			content: .highlyStructured(highlyStructuredContent()),
			timestampMilliseconds: 1_700_004_000_000
		)))

		#expect(message.protocolMessage.type == .messageEdit)
		#expect(message.protocolMessage.editedMessage.highlyStructuredMessage.elementName == "order_update")
		#expect(message.protocolMessage.editedMessage.highlyStructuredMessage.localizableParams[1].dateTime.component.year == 2026)
	}

	private func highlyStructuredContent() -> ReceivedHighlyStructuredMessageContent {
		ReceivedHighlyStructuredMessageContent(
			namespace: "commerce",
			elementName: "order_update",
			params: ["Alice", "A-123"],
			fallbackLanguage: "en",
			fallbackLocale: "US",
			localizableParams: [
				ReceivedHSMLocalizableParameterContent(
					defaultValue: "$12,345.00",
					value: .currency(ReceivedHSMCurrencyContent(currencyCode: "USD", amount1000: 12_345_000))
				),
				ReceivedHSMLocalizableParameterContent(
					defaultValue: "Friday",
					value: .dateTime(.component(ReceivedHSMDateTimeComponentContent(
						dayOfWeek: .friday,
						year: 2026,
						month: 5,
						dayOfMonth: 31,
						hour: 14,
						minute: 45,
						calendar: .gregorian
					)))
				),
				ReceivedHSMLocalizableParameterContent(
					defaultValue: nil,
					value: .dateTime(.unixEpoch(timestamp: 1_717_900_000))
				)
			],
			deterministicLanguage: "pt",
			deterministicLocale: "MZ"
		)
	}

	private func forwardedMessage(content: ReceivedMessageContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x43]))],
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
				id: "HSM1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDEDHSM"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
