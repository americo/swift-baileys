enum ForwardScheduledCallMessageMapper {
	static func creation(from content: ReceivedScheduledCallCreationContent) -> Proto_Message {
		var scheduledCall = Proto_Message.ScheduledCallCreationMessage()
		if let scheduledTimestampMilliseconds = content.scheduledTimestampMilliseconds {
			scheduledCall.scheduledTimestampMs = scheduledTimestampMilliseconds
		}
		scheduledCall.callType = callType(from: content.callType)
		if let title = content.title {
			scheduledCall.title = title
		}

		var message = Proto_Message()
		message.scheduledCallCreationMessage = scheduledCall
		return message
	}

	static func edit(from content: ReceivedScheduledCallEditContent) -> Proto_Message {
		var scheduledCall = Proto_Message.ScheduledCallEditMessage()
		if let key = content.key {
			scheduledCall.key = ForwardMessageKeyMapper.key(from: key)
		}
		scheduledCall.editType = editType(from: content.editType)

		var message = Proto_Message()
		message.scheduledCallEditMessage = scheduledCall
		return message
	}

	private static func callType(
		from type: ReceivedScheduledCallType
	) -> Proto_Message.ScheduledCallCreationMessage.CallType {
		switch type {
		case .unknown:
			.unknown
		case .voice:
			.voice
		case .video:
			.video
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}

	private static func editType(
		from type: ReceivedScheduledCallEditType
	) -> Proto_Message.ScheduledCallEditMessage.EditType {
		switch type {
		case .unknown:
			.unknown
		case .cancel:
			.cancel
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}
}
