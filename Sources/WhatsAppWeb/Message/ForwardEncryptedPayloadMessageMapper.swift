enum ForwardEncryptedPayloadMessageMapper {
	static func encryptedComment(from content: ReceivedEncryptedCommentContent) -> Proto_Message {
		var comment = Proto_Message.EncCommentMessage()
		if let targetMessageKey = content.targetMessageKey {
			comment.targetMessageKey = ForwardMessageKeyMapper.key(from: targetMessageKey)
		}
		if let encryptedPayload = content.encryptedPayload {
			comment.encPayload = encryptedPayload
		}
		if let encryptedIV = content.encryptedIV {
			comment.encIv = encryptedIV
		}
		var message = Proto_Message()
		message.encCommentMessage = comment
		return message
	}

	static func encryptedReaction(from content: ReceivedEncryptedReactionContent) -> Proto_Message {
		var reaction = Proto_Message.EncReactionMessage()
		if let targetMessageKey = content.targetMessageKey {
			reaction.targetMessageKey = ForwardMessageKeyMapper.key(from: targetMessageKey)
		}
		if let encryptedPayload = content.encryptedPayload {
			reaction.encPayload = encryptedPayload
		}
		if let encryptedIV = content.encryptedIV {
			reaction.encIv = encryptedIV
		}
		var message = Proto_Message()
		message.encReactionMessage = reaction
		return message
	}

	static func secretEncrypted(from content: ReceivedSecretEncryptedContent) -> Proto_Message {
		var secret = Proto_Message.SecretEncryptedMessage()
		if let targetMessageKey = content.targetMessageKey {
			secret.targetMessageKey = ForwardMessageKeyMapper.key(from: targetMessageKey)
		}
		if let encryptedPayload = content.encryptedPayload {
			secret.encPayload = encryptedPayload
		}
		if let encryptedIV = content.encryptedIV {
			secret.encIv = encryptedIV
		}
		if let type = content.type {
			secret.secretEncType = switch type {
			case .unknown:
				.unknown
			case .eventEdit:
				.eventEdit
			case .messageEdit:
				.messageEdit
			case .unrecognized(let value):
				.UNRECOGNIZED(value)
			}
		}
		var message = Proto_Message()
		message.secretEncryptedMessage = secret
		return message
	}
}
