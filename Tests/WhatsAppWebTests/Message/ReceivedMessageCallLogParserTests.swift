import Testing
@testable import WhatsAppWeb

@Suite("Received message call log parser")
struct ReceivedMessageCallLogParserTests {
	@Test("parses call log messages")
	func parsesCallLogMessages() throws {
		var firstParticipant = Proto_Message.CallLogMessage.CallParticipant()
		firstParticipant.jid = "258840000001@s.whatsapp.net"
		firstParticipant.callOutcome = .connected
		var secondParticipant = Proto_Message.CallLogMessage.CallParticipant()
		secondParticipant.jid = "258840000002@s.whatsapp.net"
		secondParticipant.callOutcome = .rejected
		var callLog = Proto_Message.CallLogMessage()
		callLog.isVideo = true
		callLog.callOutcome = .missed
		callLog.durationSecs = 42
		callLog.callType = .voiceChat
		callLog.participants = [firstParticipant, secondParticipant]
		var message = Proto_Message()
		message.callLogMesssage = callLog

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .callLog(ReceivedCallLogContent(
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
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent optional call log fields")
	func preservesAbsentOptionalCallLogFields() throws {
		var participant = Proto_Message.CallLogMessage.CallParticipant()
		participant.jid = "258840000003@s.whatsapp.net"
		var callLog = Proto_Message.CallLogMessage()
		callLog.participants = [participant]
		var message = Proto_Message()
		message.callLogMesssage = callLog

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .callLog(ReceivedCallLogContent(
			isVideo: nil,
			outcome: nil,
			durationSeconds: nil,
			callType: nil,
			participants: [
				ReceivedCallLogParticipant(
					jid: "258840000003@s.whatsapp.net",
					outcome: nil
				)
			]
		)))
	}
}
