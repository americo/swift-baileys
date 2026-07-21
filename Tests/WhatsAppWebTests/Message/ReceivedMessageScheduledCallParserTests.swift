import Testing
@testable import WhatsAppWeb

@Suite("Received message scheduled call parser")
struct ReceivedMessageScheduledCallParserTests {
	@Test("parses scheduled call creation messages")
	func parsesScheduledCallCreationMessages() throws {
		var scheduledCall = Proto_Message.ScheduledCallCreationMessage()
		scheduledCall.scheduledTimestampMs = 1_700_200_000_000
		scheduledCall.callType = .video
		scheduledCall.title = "Weekly sync"
		var message = Proto_Message()
		message.scheduledCallCreationMessage = scheduledCall

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .scheduledCallCreation(ReceivedScheduledCallCreationContent(
			scheduledTimestampMilliseconds: 1_700_200_000_000,
			callType: .video,
			title: "Weekly sync"
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses scheduled call edit messages")
	func parsesScheduledCallEditMessages() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "120363000000000000@g.us"
		key.fromMe = false
		key.id = "SCHEDULED_CALL_MESSAGE_ID"
		key.participant = "258840000000@s.whatsapp.net"
		var scheduledCall = Proto_Message.ScheduledCallEditMessage()
		scheduledCall.key = key
		scheduledCall.editType = .cancel
		var message = Proto_Message()
		message.scheduledCallEditMessage = scheduledCall

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .scheduledCallEdit(ReceivedScheduledCallEditContent(
			key: ReceivedMessageKey(
				remoteJID: "120363000000000000@g.us",
				fromMe: false,
				id: "SCHEDULED_CALL_MESSAGE_ID",
				participant: "258840000000@s.whatsapp.net"
			),
			editType: .cancel
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}
}
