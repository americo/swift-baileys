enum ReceivedWebMessageInfoParser {
	static func parse(_ info: Proto_WebMessageInfo) -> ReceivedMessage? {
		guard info.hasKey, info.key.hasID else {
			return nil
		}

		let stub = info.hasMessageStubType
			? ReceivedMessageStubContent(
				type: ReceivedMessageStubType(rawValue: info.messageStubType.rawValue),
				parameters: info.messageStubParameters
			)
			: nil
		let content = info.hasMessage
			? ReceivedMessageContentParser.parse(info.message)
			: stub.map(ReceivedMessageContent.stub)

		guard let content else {
			return nil
		}

		return ReceivedMessage(
			id: info.key.id,
			from: info.key.hasRemoteJid ? info.key.remoteJid : nil,
			timestamp: info.hasMessageTimestamp ? info.messageTimestamp : nil,
			content: content,
			fromMe: info.key.hasFromMe ? info.key.fromMe : nil,
			participant: info.hasParticipant ? info.participant : nil,
			keyParticipant: info.key.hasParticipant ? info.key.participant : nil,
			status: info.hasStatus ? messageStatus(info.status) : nil,
			pushName: info.hasPushName ? info.pushName : nil,
			stub: stub
		)
	}

	private static func messageStatus(_ status: Proto_WebMessageInfo.Status) -> ReceivedMessageStatus {
		switch status {
		case .error:
			.error
		case .pending:
			.pending
		case .serverAck:
			.serverAck
		case .deliveryAck:
			.deliveryAck
		case .read:
			.read
		case .played:
			.played
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}
}
