enum ForwardMessageActionMessageMapper {
	static func pin(from content: ReceivedMessagePinContent) -> Proto_Message {
		var pin = Proto_Message.PinInChatMessage()
		if let key = content.key {
			pin.key = ForwardMessageKeyMapper.key(from: key)
		}
		pin.type = switch content.action {
		case .unknown:
			.unknownType
		case .pinForAll:
			.pinForAll
		case .unpinForAll:
			.unpinForAll
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
		if let senderTimestampMilliseconds = content.senderTimestampMilliseconds {
			pin.senderTimestampMs = senderTimestampMilliseconds
		}

		var message = Proto_Message()
		message.pinInChatMessage = pin
		return message
	}

	static func keep(from content: ReceivedMessageKeepContent) -> Proto_Message {
		var keep = Proto_Message.KeepInChatMessage()
		if let key = content.key {
			keep.key = ForwardMessageKeyMapper.key(from: key)
		}
		keep.keepType = switch content.action {
		case .unknown:
			.unknown
		case .keepForAll:
			.keepForAll
		case .undoKeepForAll:
			.undoKeepForAll
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
		if let timestampMilliseconds = content.timestampMilliseconds {
			keep.timestampMs = timestampMilliseconds
		}

		var message = Proto_Message()
		message.keepInChatMessage = keep
		return message
	}
}
