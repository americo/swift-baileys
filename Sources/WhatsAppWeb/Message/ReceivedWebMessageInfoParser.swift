import Foundation

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
			stub: stub,
			messageSecret: info.hasMessage ? secret(of: info.message) : nil,
			reactions: info.reactions.map(reaction),
			starred: info.starred,
			textStyle: info.hasMessage ? textStyle(of: info.message) : nil,
			isViewOnce: info.hasMessage && MessageContentNormalizer.isViewOnce(info.message)
		)
	}

	private static func reaction(_ reaction: Proto_Reaction) -> ReceivedReactionContent {
		ReceivedReactionContent(
			key: reaction.hasKey ? ReceivedMessageContentParser.messageKey(reaction.key) : nil,
			text: reaction.hasText ? reaction.text : nil,
			groupingKey: reaction.hasGroupingKey ? reaction.groupingKey : nil,
			senderTimestampMilliseconds: reaction.hasSenderTimestampMs ? reaction.senderTimestampMs : nil
		)
	}

	static func textStyle(of message: Proto_Message) -> ReceivedTextStyle? {
		let normalized = MessageContentNormalizer.normalized(message)
		guard normalized.hasExtendedTextMessage else { return nil }
		let text = normalized.extendedTextMessage
		guard text.hasBackgroundArgb || text.hasTextArgb else { return nil }
		return ReceivedTextStyle(
			backgroundARGB: text.hasBackgroundArgb ? text.backgroundArgb : nil,
			textARGB: text.hasTextArgb ? text.textArgb : nil
		)
	}

	static func secret(of message: Proto_Message) -> Data? {
		guard message.hasMessageContextInfo else { return nil }
		let secret = message.messageContextInfo.messageSecret
		return secret.isEmpty ? nil : secret
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
