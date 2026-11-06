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
			isViewOnce: info.hasMessage && MessageContentNormalizer.isViewOnce(info.message),
			quote: info.hasMessage ? quote(of: info.message) : nil
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

	static func quote(of message: Proto_Message) -> ReceivedQuote? {
		let m = MessageContentNormalizer.normalized(message)
		let context: Proto_ContextInfo?
		if m.hasExtendedTextMessage, m.extendedTextMessage.hasContextInfo { context = m.extendedTextMessage.contextInfo }
		else if m.hasImageMessage, m.imageMessage.hasContextInfo { context = m.imageMessage.contextInfo }
		else if m.hasVideoMessage, m.videoMessage.hasContextInfo { context = m.videoMessage.contextInfo }
		else if m.hasAudioMessage, m.audioMessage.hasContextInfo { context = m.audioMessage.contextInfo }
		else if m.hasDocumentMessage, m.documentMessage.hasContextInfo { context = m.documentMessage.contextInfo }
		else if m.hasStickerMessage, m.stickerMessage.hasContextInfo { context = m.stickerMessage.contextInfo }
		else { context = nil }
		guard let context, context.hasStanzaID, !context.stanzaID.isEmpty else { return nil }
		var text: String?
		if context.hasQuotedMessage {
			let quoted = MessageContentNormalizer.normalized(context.quotedMessage)
			if !quoted.conversation.isEmpty { text = quoted.conversation }
			else if quoted.hasExtendedTextMessage { text = quoted.extendedTextMessage.text }
			else if quoted.hasImageMessage { text = quoted.imageMessage.caption }
			else if quoted.hasVideoMessage { text = quoted.videoMessage.caption }
		}
		return ReceivedQuote(
			messageID: context.stanzaID,
			participant: context.hasParticipant ? context.participant : nil,
			remoteJID: context.hasRemoteJid ? context.remoteJid : nil,
			text: text?.isEmpty == true ? nil : text
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
