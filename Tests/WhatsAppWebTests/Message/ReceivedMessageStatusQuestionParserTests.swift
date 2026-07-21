import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message status and question parser")
struct ReceivedMessageStatusQuestionParserTests {
	@Test("parses status notification messages")
	func parsesStatusNotificationMessages() throws {
		var responseKey = Proto_MessageKey()
		responseKey.remoteJid = "status@broadcast"
		responseKey.id = "response-id"
		var originalKey = Proto_MessageKey()
		originalKey.remoteJid = "123@s.whatsapp.net"
		originalKey.fromMe = true
		originalKey.id = "original-id"
		var statusNotification = Proto_Message.StatusNotificationMessage()
		statusNotification.responseMessageKey = responseKey
		statusNotification.originalMessageKey = originalKey
		statusNotification.type = .statusQuestionAnswerReshare
		var message = Proto_Message()
		message.statusNotificationMessage = statusNotification

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .statusNotification(ReceivedStatusNotificationContent(
			responseMessageKey: ReceivedMessageKey(remoteJID: "status@broadcast", fromMe: false, id: "response-id", participant: nil),
			originalMessageKey: ReceivedMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: true, id: "original-id", participant: nil),
			type: .statusQuestionAnswerReshare
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses question response messages")
	func parsesQuestionResponseMessages() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "status@broadcast"
		key.id = "question-id"
		var questionResponse = Proto_Message.QuestionResponseMessage()
		questionResponse.key = key
		questionResponse.text = "Resposta"
		var message = Proto_Message()
		message.questionResponseMessage = questionResponse

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .questionResponse(ReceivedQuestionResponseContent(
			key: ReceivedMessageKey(remoteJID: "status@broadcast", fromMe: false, id: "question-id", participant: nil),
			text: "Resposta"
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses status question answer messages")
	func parsesStatusQuestionAnswerMessages() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "status@broadcast"
		key.id = "answer-id"
		var statusQuestionAnswer = Proto_Message.StatusQuestionAnswerMessage()
		statusQuestionAnswer.key = key
		statusQuestionAnswer.text = "Answer text"
		var message = Proto_Message()
		message.statusQuestionAnswerMessage = statusQuestionAnswer

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .statusQuestionAnswer(ReceivedStatusQuestionAnswerContent(
			key: ReceivedMessageKey(remoteJID: "status@broadcast", fromMe: false, id: "answer-id", participant: nil),
			text: "Answer text"
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses status quoted messages")
	func parsesStatusQuotedMessages() throws {
		var originalKey = Proto_MessageKey()
		originalKey.remoteJid = "status@broadcast"
		originalKey.id = "quoted-id"
		var statusQuoted = Proto_Message.StatusQuotedMessage()
		statusQuoted.type = .questionAnswer
		statusQuoted.text = "Quoted status"
		statusQuoted.thumbnail = Data([5, 6, 7])
		statusQuoted.originalStatusID = originalKey
		var message = Proto_Message()
		message.statusQuotedMessage = statusQuoted

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .statusQuoted(ReceivedStatusQuotedContent(
			type: .questionAnswer,
			text: "Quoted status",
			thumbnail: Data([5, 6, 7]),
			originalStatusID: ReceivedMessageKey(remoteJID: "status@broadcast", fromMe: false, id: "quoted-id", participant: nil)
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses status sticker interaction messages")
	func parsesStatusStickerInteractionMessages() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "status@broadcast"
		key.id = "sticker-status-id"
		var interaction = Proto_Message.StatusStickerInteractionMessage()
		interaction.key = key
		interaction.stickerKey = "sticker-key"
		interaction.type = .reaction
		var message = Proto_Message()
		message.statusStickerInteractionMessage = interaction

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .statusStickerInteraction(ReceivedStatusStickerInteractionContent(
			key: ReceivedMessageKey(remoteJID: "status@broadcast", fromMe: false, id: "sticker-status-id", participant: nil),
			stickerKey: "sticker-key",
			type: .reaction
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent optional status interaction fields")
	func preservesAbsentOptionalStatusInteractionFields() throws {
		var message = Proto_Message()
		message.statusQuotedMessage = Proto_Message.StatusQuotedMessage()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .statusQuoted(ReceivedStatusQuotedContent(
			type: nil,
			text: nil,
			thumbnail: nil,
			originalStatusID: nil
		)))
	}
}
