enum ForwardPlaceholderMessageMapper {
	static func message(from content: ReceivedPlaceholderContent) -> Proto_Message {
		var placeholder = Proto_Message.PlaceholderMessage()
		if let type = content.type {
			placeholder.type = switch type {
			case .maskLinkedDevices:
				.maskLinkedDevices
			case .unrecognized(let value):
				.UNRECOGNIZED(value)
			}
		}

		var message = Proto_Message()
		message.placeholderMessage = placeholder
		return message
	}
}
