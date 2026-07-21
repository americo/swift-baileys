import Foundation

public struct AppStateChatRangeMessage: Equatable, Sendable {
	public var key: WhatsAppMessageKey
	public var timestamp: Int64

	public init(key: WhatsAppMessageKey, timestamp: Int64) {
		self.key = key
		self.timestamp = timestamp
	}
}

public struct AppStateChatMessageRange: Equatable, Sendable {
	public var lastMessageTimestamp: Int64?
	public var lastSystemMessageTimestamp: Int64?
	public var messages: [AppStateChatRangeMessage]

	public init(
		lastMessageTimestamp: Int64? = nil,
		lastSystemMessageTimestamp: Int64? = nil,
		messages: [AppStateChatRangeMessage] = []
	) {
		self.lastMessageTimestamp = lastMessageTimestamp
		self.lastSystemMessageTimestamp = lastSystemMessageTimestamp
		self.messages = messages
	}
}

public enum AppStateChatMessageRangeError: Error, Equatable, Sendable {
	case incompleteKey
	case missingTimestamp
	case expectedGroupParticipant
}

extension AppStateChatMessageRange {
	func proto() throws -> Proto_SyncActionValue.SyncActionMessageRange {
		var range = Proto_SyncActionValue.SyncActionMessageRange()
		if let lastMessageTimestamp {
			range.lastMessageTimestamp = lastMessageTimestamp
		} else if let lastMessage = messages.last {
			range.lastMessageTimestamp = lastMessage.timestamp
		}
		if let lastSystemMessageTimestamp {
			range.lastSystemMessageTimestamp = lastSystemMessageTimestamp
		}
		range.messages = try messages.map { message in
			guard message.timestamp != 0 else {
				throw AppStateChatMessageRangeError.missingTimestamp
			}
			guard let id = message.key.id, let remoteJID = message.key.remoteJID else {
				throw AppStateChatMessageRangeError.incompleteKey
			}
			if remoteJID.isGroupJID && !message.key.fromMe && message.key.participant == nil {
				throw AppStateChatMessageRangeError.expectedGroupParticipant
			}

			var key = Proto_MessageKey()
			key.remoteJid = remoteJID
			key.fromMe = message.key.fromMe
			key.id = id
			if let participant = message.key.participant {
				key.participant = JID(participant)?.normalizedUser ?? participant
			}

			var syncMessage = Proto_SyncActionValue.SyncActionMessage()
			syncMessage.key = key
			syncMessage.timestamp = message.timestamp
			return syncMessage
		}
		return range
	}
}
