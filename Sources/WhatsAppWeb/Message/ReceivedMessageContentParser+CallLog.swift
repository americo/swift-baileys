extension ReceivedMessageContentParser {
	static func callLogContent(_ callLog: Proto_Message.CallLogMessage) -> ReceivedCallLogContent {
		ReceivedCallLogContent(
			isVideo: callLog.hasIsVideo ? callLog.isVideo : nil,
			outcome: callLog.hasCallOutcome ? callLogOutcome(callLog.callOutcome) : nil,
			durationSeconds: callLog.hasDurationSecs ? callLog.durationSecs : nil,
			callType: callLog.hasCallType ? callLogType(callLog.callType) : nil,
			participants: callLog.participants.map {
				ReceivedCallLogParticipant(
					jid: $0.hasJid ? $0.jid : nil,
					outcome: $0.hasCallOutcome ? callLogOutcome($0.callOutcome) : nil
				)
			}
		)
	}

	static func callLogOutcome(_ outcome: Proto_Message.CallLogMessage.CallOutcome) -> ReceivedCallLogOutcome {
		switch outcome {
		case .connected:
			.connected
		case .missed:
			.missed
		case .failed:
			.failed
		case .rejected:
			.rejected
		case .acceptedElsewhere:
			.acceptedElsewhere
		case .ongoing:
			.ongoing
		case .silencedByDnd:
			.silencedByDnd
		case .silencedUnknownCaller:
			.silencedUnknownCaller
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	static func callLogType(_ type: Proto_Message.CallLogMessage.CallType) -> ReceivedCallLogType {
		switch type {
		case .regular:
			.regular
		case .scheduledCall:
			.scheduledCall
		case .voiceChat:
			.voiceChat
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}
}
