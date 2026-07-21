extension ReceivedMessageContentParser {
	static func businessCallContent(_ bcall: Proto_Message.BCallMessage) -> ReceivedBusinessCallContent {
		ReceivedBusinessCallContent(
			sessionID: bcall.hasSessionID ? bcall.sessionID : nil,
			mediaType: bcall.hasMediaType ? businessCallMediaType(bcall.mediaType) : nil,
			masterKey: bcall.hasMasterKey ? bcall.masterKey : nil,
			caption: bcall.hasCaption ? bcall.caption : nil
		)
	}

	private static func businessCallMediaType(
		_ mediaType: Proto_Message.BCallMessage.MediaType
	) -> ReceivedBusinessCallMediaType {
		switch mediaType {
		case .unknown:
			.unknown
		case .audio:
			.audio
		case .video:
			.video
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}
}
