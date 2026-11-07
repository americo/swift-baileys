/// What every kind of outgoing message can carry besides its content.
public struct OutgoingMessageContext: Equatable, Sendable {
	public static let none = OutgoingMessageContext()

	public var isForwarded: Bool
	/// How many times the message was forwarded, counting this time.
	public var forwardingScore: UInt32?
	/// The chat's disappearing messages timer, in seconds.
	public var ephemeralExpiration: UInt32?

	public init(isForwarded: Bool = false, forwardingScore: UInt32? = nil, ephemeralExpiration: UInt32? = nil) {
		self.isForwarded = isForwarded
		self.forwardingScore = forwardingScore
		self.ephemeralExpiration = ephemeralExpiration
	}
}

extension MessageContentBuilder {
	static func applying(_ context: OutgoingMessageContext, to content: Proto_Message) -> Proto_Message {
		guard context != .none else { return content }

		func merged(_ existing: Proto_ContextInfo) -> Proto_ContextInfo {
			var info = existing
			if context.isForwarded {
				info.isForwarded = true
			}
			if let score = context.forwardingScore {
				info.forwardingScore = score
			}
			if let expiration = context.ephemeralExpiration, expiration > 0 {
				info.expiration = expiration
			}
			return info
		}

		var message = content
		if message.hasConversation {
			var text = Proto_Message.ExtendedTextMessage()
			text.text = message.conversation
			message.clearConversation()
			message.extendedTextMessage = text
		}
		if message.hasExtendedTextMessage {
			message.extendedTextMessage.contextInfo = merged(message.extendedTextMessage.contextInfo)
		} else if message.hasImageMessage {
			message.imageMessage.contextInfo = merged(message.imageMessage.contextInfo)
		} else if message.hasVideoMessage {
			message.videoMessage.contextInfo = merged(message.videoMessage.contextInfo)
		} else if message.hasAudioMessage {
			message.audioMessage.contextInfo = merged(message.audioMessage.contextInfo)
		} else if message.hasDocumentMessage {
			message.documentMessage.contextInfo = merged(message.documentMessage.contextInfo)
		} else if message.hasStickerMessage {
			message.stickerMessage.contextInfo = merged(message.stickerMessage.contextInfo)
		} else if message.hasContactMessage {
			message.contactMessage.contextInfo = merged(message.contactMessage.contextInfo)
		} else if message.hasContactsArrayMessage {
			message.contactsArrayMessage.contextInfo = merged(message.contactsArrayMessage.contextInfo)
		} else if message.hasLocationMessage {
			message.locationMessage.contextInfo = merged(message.locationMessage.contextInfo)
		} else if message.hasPollCreationMessage {
			message.pollCreationMessage.contextInfo = merged(message.pollCreationMessage.contextInfo)
		} else if message.hasPollCreationMessageV2 {
			message.pollCreationMessageV2.contextInfo = merged(message.pollCreationMessageV2.contextInfo)
		} else if message.hasPollCreationMessageV3 {
			message.pollCreationMessageV3.contextInfo = merged(message.pollCreationMessageV3.contextInfo)
		}
		return message
	}
}
