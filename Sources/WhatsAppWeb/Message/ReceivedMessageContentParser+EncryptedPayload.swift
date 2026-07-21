extension ReceivedMessageContentParser {
	static func encryptedCommentContent(
		_ comment: Proto_Message.EncCommentMessage
	) -> ReceivedEncryptedCommentContent {
		ReceivedEncryptedCommentContent(
			targetMessageKey: comment.hasTargetMessageKey ? messageKey(comment.targetMessageKey) : nil,
			encryptedPayload: comment.hasEncPayload ? comment.encPayload : nil,
			encryptedIV: comment.hasEncIv ? comment.encIv : nil
		)
	}

	static func encryptedReactionContent(
		_ reaction: Proto_Message.EncReactionMessage
	) -> ReceivedEncryptedReactionContent {
		ReceivedEncryptedReactionContent(
			targetMessageKey: reaction.hasTargetMessageKey ? messageKey(reaction.targetMessageKey) : nil,
			encryptedPayload: reaction.hasEncPayload ? reaction.encPayload : nil,
			encryptedIV: reaction.hasEncIv ? reaction.encIv : nil
		)
	}

	static func secretEncryptedContent(
		_ secret: Proto_Message.SecretEncryptedMessage
	) -> ReceivedSecretEncryptedContent {
		ReceivedSecretEncryptedContent(
			targetMessageKey: secret.hasTargetMessageKey ? messageKey(secret.targetMessageKey) : nil,
			encryptedPayload: secret.hasEncPayload ? secret.encPayload : nil,
			encryptedIV: secret.hasEncIv ? secret.encIv : nil,
			type: secret.hasSecretEncType ? secretEncryptedType(secret.secretEncType) : nil
		)
	}

	private static func secretEncryptedType(
		_ type: Proto_Message.SecretEncryptedMessage.SecretEncType
	) -> ReceivedSecretEncryptedType {
		switch type {
		case .unknown:
			.unknown
		case .eventEdit:
			.eventEdit
		case .messageEdit:
			.messageEdit
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}
}
