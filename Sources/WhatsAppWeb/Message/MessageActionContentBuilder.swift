import Foundation

public enum MessagePinAction: Sendable {
	case pin
	case unpin
}

extension MessageContentBuilder {
	static func delete(target: WhatsAppMessageKey) -> Proto_Message {
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.key = protoKey(from: target)
		protocolMessage.type = .revoke

		var message = Proto_Message()
		message.protocolMessage = protocolMessage
		return message
	}

	static func edit(
		target: WhatsAppMessageKey,
		message: Proto_Message,
		timestampMilliseconds: Int64
	) -> Proto_Message {
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.key = protoKey(from: target)
		protocolMessage.type = .messageEdit
		protocolMessage.editedMessage = message
		protocolMessage.timestampMs = timestampMilliseconds

		var wrapper = Proto_Message()
		wrapper.protocolMessage = protocolMessage
		return wrapper
	}

	static func pin(
		target: WhatsAppMessageKey,
		action: MessagePinAction,
		duration: UInt32,
		timestampMilliseconds: Int64
	) -> Proto_Message {
		var pin = Proto_Message.PinInChatMessage()
		pin.key = protoKey(from: target)
		pin.type = action == .pin ? .pinForAll : .unpinForAll
		pin.senderTimestampMs = timestampMilliseconds

		var context = Proto_MessageContextInfo()
		context.messageAddOnDurationInSecs = action == .pin ? duration : 0

		var message = Proto_Message()
		message.pinInChatMessage = pin
		message.messageContextInfo = context
		return message
	}

	static func sharePhoneNumber() -> Proto_Message {
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .sharePhoneNumber

		var message = Proto_Message()
		message.protocolMessage = protocolMessage
		return message
	}

	static func limitSharing(_ content: OutgoingLimitSharingContent) -> Proto_Message {
		var limitSharing = Proto_LimitSharing()
		limitSharing.sharingLimited = content.sharingLimited
		limitSharing.trigger = .chatSetting
		limitSharing.limitSharingSettingTimestamp = content.settingTimestampMilliseconds
		limitSharing.initiatedByMe = true

		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .limitSharing
		protocolMessage.limitSharing = limitSharing

		var message = Proto_Message()
		message.protocolMessage = protocolMessage
		return message
	}

	static func disappearingMessages(_ content: OutgoingDisappearingMessagesContent) -> Proto_Message {
		disappearingMessageSetting(expirationSeconds: content.expirationSeconds)
	}

	static func disappearingMessageSetting(expirationSeconds: UInt32? = nil) -> Proto_Message {
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .ephemeralSetting
		protocolMessage.ephemeralExpiration = expirationSeconds ?? 0

		var innerMessage = Proto_Message()
		innerMessage.protocolMessage = protocolMessage

		var futureProof = Proto_Message.FutureProofMessage()
		futureProof.message = innerMessage

		var message = Proto_Message()
		message.ephemeralMessage = futureProof
		return message
	}

	private static func protoKey(from key: WhatsAppMessageKey) -> Proto_MessageKey {
		var protoKey = Proto_MessageKey()
		if let remoteJID = key.remoteJID {
			protoKey.remoteJid = remoteJID
		}

		protoKey.fromMe = key.fromMe
		if let id = key.id {
			protoKey.id = id
		}

		if let participant = key.participant {
			protoKey.participant = participant
		}

		return protoKey
	}
}
