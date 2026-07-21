import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward status and question messages")
struct WhatsAppClientForwardStatusQuestionMessageTests {
	@Test("forwards received status and question messages through the encrypted send path")
	func forwardsReceivedStatusAndQuestionMessagesThroughEncryptedSendPath() async throws {
		let responseKey = ReceivedMessageKey(
			remoteJID: "status@broadcast",
			fromMe: false,
			id: "response-id",
			participant: nil
		)
		let originalKey = ReceivedMessageKey(
			remoteJID: "123@s.whatsapp.net",
			fromMe: true,
			id: "original-id",
			participant: nil
		)

		let statusNotification = try await forwardedMessage(content: .statusNotification(
			ReceivedStatusNotificationContent(
				responseMessageKey: responseKey,
				originalMessageKey: originalKey,
				type: .statusQuestionAnswerReshare
			)
		))
		#expect(statusNotification.hasStatusNotificationMessage)
		#expect(statusNotification.statusNotificationMessage.responseMessageKey.remoteJid == "status@broadcast")
		#expect(statusNotification.statusNotificationMessage.responseMessageKey.id == "response-id")
		#expect(statusNotification.statusNotificationMessage.originalMessageKey.remoteJid == "123@s.whatsapp.net")
		#expect(statusNotification.statusNotificationMessage.originalMessageKey.fromMe)
		#expect(statusNotification.statusNotificationMessage.type == .statusQuestionAnswerReshare)

		let statusQuestionAnswer = try await forwardedMessage(content: .statusQuestionAnswer(
			ReceivedStatusQuestionAnswerContent(key: responseKey, text: "Answer text")
		))
		#expect(statusQuestionAnswer.hasStatusQuestionAnswerMessage)
		#expect(statusQuestionAnswer.statusQuestionAnswerMessage.key.remoteJid == "status@broadcast")
		#expect(statusQuestionAnswer.statusQuestionAnswerMessage.key.id == "response-id")
		#expect(statusQuestionAnswer.statusQuestionAnswerMessage.text == "Answer text")

		let questionResponse = try await forwardedMessage(content: .questionResponse(
			ReceivedQuestionResponseContent(key: responseKey, text: "Resposta")
		))
		#expect(questionResponse.hasQuestionResponseMessage)
		#expect(questionResponse.questionResponseMessage.key.remoteJid == "status@broadcast")
		#expect(questionResponse.questionResponseMessage.key.id == "response-id")
		#expect(questionResponse.questionResponseMessage.text == "Resposta")

		let statusQuoted = try await forwardedMessage(content: .statusQuoted(
			ReceivedStatusQuotedContent(
				type: .questionAnswer,
				text: "Quoted status",
				thumbnail: Data([5, 6, 7]),
				originalStatusID: responseKey
			)
		))
		#expect(statusQuoted.hasStatusQuotedMessage)
		#expect(statusQuoted.statusQuotedMessage.type == .questionAnswer)
		#expect(statusQuoted.statusQuotedMessage.text == "Quoted status")
		#expect(statusQuoted.statusQuotedMessage.thumbnail == Data([5, 6, 7]))
		#expect(statusQuoted.statusQuotedMessage.originalStatusID.id == "response-id")

		let stickerInteraction = try await forwardedMessage(content: .statusStickerInteraction(
			ReceivedStatusStickerInteractionContent(
				key: responseKey,
				stickerKey: "sticker-key",
				type: .reaction
			)
		))
		#expect(stickerInteraction.hasStatusStickerInteractionMessage)
		#expect(stickerInteraction.statusStickerInteractionMessage.key.id == "response-id")
		#expect(stickerInteraction.statusStickerInteractionMessage.stickerKey == "sticker-key")
		#expect(stickerInteraction.statusStickerInteractionMessage.type == .reaction)
	}

	private func forwardedMessage(content: ReceivedMessageContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x28]))],
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
				id: "STATUSQUESTION1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDEDSTATUSQUESTION"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
