enum ForwardCallLogMessageMapper {
	static func message(from content: ReceivedCallLogContent) -> Proto_Message {
		var callLog = Proto_Message.CallLogMessage()
		if let isVideo = content.isVideo {
			callLog.isVideo = isVideo
		}
		if let outcome = content.outcome {
			callLog.callOutcome = callOutcome(from: outcome)
		}
		if let durationSeconds = content.durationSeconds {
			callLog.durationSecs = durationSeconds
		}
		if let type = content.callType {
			callLog.callType = callType(from: type)
		}
		callLog.participants = content.participants.map {
			var participant = Proto_Message.CallLogMessage.CallParticipant()
			if let jid = $0.jid {
				participant.jid = jid
			}
			if let outcome = $0.outcome {
				participant.callOutcome = callOutcome(from: outcome)
			}
			return participant
		}

		var message = Proto_Message()
		message.callLogMesssage = callLog
		return message
	}

	private static func callOutcome(
		from outcome: ReceivedCallLogOutcome
	) -> Proto_Message.CallLogMessage.CallOutcome {
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
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}

	private static func callType(
		from type: ReceivedCallLogType
	) -> Proto_Message.CallLogMessage.CallType {
		switch type {
		case .regular:
			.regular
		case .scheduledCall:
			.scheduledCall
		case .voiceChat:
			.voiceChat
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}
}
