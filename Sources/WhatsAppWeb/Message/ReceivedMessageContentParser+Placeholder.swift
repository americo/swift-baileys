extension ReceivedMessageContentParser {
	static func placeholderContent(_ placeholder: Proto_Message.PlaceholderMessage) -> ReceivedPlaceholderContent {
		ReceivedPlaceholderContent(
			type: placeholder.hasType ? placeholderType(placeholder.type) : nil
		)
	}

	private static func placeholderType(
		_ type: Proto_Message.PlaceholderMessage.PlaceholderType
	) -> ReceivedPlaceholderType {
		switch type {
		case .maskLinkedDevices:
			.maskLinkedDevices
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}
}
