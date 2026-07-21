import Foundation

public enum MessagingHistoryStatus: String, Equatable, Sendable {
	case complete
	case paused
}

public struct MessagingHistoryStatusUpdate: Equatable, Sendable {
	public let syncType: ReceivedHistorySyncType
	public let status: MessagingHistoryStatus
	public let explicit: Bool

	public init(syncType: ReceivedHistorySyncType, status: MessagingHistoryStatus, explicit: Bool) {
		self.syncType = syncType
		self.status = status
		self.explicit = explicit
	}
}

public struct MessagingHistorySet: Equatable, Sendable {
	public let chats: [HistorySyncChat]
	public let contacts: [HistorySyncContact]
	public let messages: [ReceivedMessage]
	public let lidPnMappings: [LIDMapping]
	public let pastParticipants: [HistorySyncPastParticipants]
	public let syncType: ReceivedHistorySyncType
	public let progress: UInt32?
	public let chunkOrder: UInt32?
	public let peerDataRequestSessionID: String?
	public let isLatest: Bool?

	public init(
		chats: [HistorySyncChat],
		contacts: [HistorySyncContact],
		messages: [ReceivedMessage],
		lidPnMappings: [LIDMapping],
		pastParticipants: [HistorySyncPastParticipants],
		syncType: ReceivedHistorySyncType,
		progress: UInt32?,
		chunkOrder: UInt32? = nil,
		peerDataRequestSessionID: String? = nil,
		isLatest: Bool? = nil
	) {
		self.chats = chats
		self.contacts = contacts
		self.messages = messages
		self.lidPnMappings = lidPnMappings
		self.pastParticipants = pastParticipants
		self.syncType = syncType
		self.progress = progress
		self.chunkOrder = chunkOrder
		self.peerDataRequestSessionID = peerDataRequestSessionID
		self.isLatest = isLatest
	}

	func withNotificationMetadata(
		from notification: ReceivedHistorySyncNotificationContent,
		isLatest: Bool? = nil
	) -> MessagingHistorySet {
		MessagingHistorySet(
			chats: chats,
			contacts: contacts,
			messages: messages,
			lidPnMappings: lidPnMappings,
			pastParticipants: pastParticipants,
			syncType: syncType,
			progress: progress,
			chunkOrder: notification.chunkOrder,
			peerDataRequestSessionID: notification.peerDataRequestSessionID,
			isLatest: isLatest
		)
	}
}

public struct HistorySyncChat: Equatable, Sendable {
	public let id: String
	public let name: String?
	public let displayName: String?
	public let username: String?
	public let lid: String?
	public let phoneNumber: String?
	public let lastMessageReceivedTimestamp: UInt64?
	public let latestMessage: ReceivedMessage?

	public init(
		id: String,
		name: String?,
		displayName: String?,
		username: String?,
		lid: String?,
		phoneNumber: String?,
		lastMessageReceivedTimestamp: UInt64?,
		latestMessage: ReceivedMessage?
	) {
		self.id = id
		self.name = name
		self.displayName = displayName
		self.username = username
		self.lid = lid
		self.phoneNumber = phoneNumber
		self.lastMessageReceivedTimestamp = lastMessageReceivedTimestamp
		self.latestMessage = latestMessage
	}
}

public struct HistorySyncContact: Equatable, Sendable {
	public let id: String
	public let name: String?
	public let username: String?
	public let lid: String?
	public let phoneNumber: String?
	public let notify: String?
	public let verifiedName: String?

	public init(
		id: String,
		name: String?,
		username: String?,
		lid: String?,
		phoneNumber: String?,
		notify: String?,
		verifiedName: String?
	) {
		self.id = id
		self.name = name
		self.username = username
		self.lid = lid
		self.phoneNumber = phoneNumber
		self.notify = notify
		self.verifiedName = verifiedName
	}
}

public struct HistorySyncPastParticipants: Equatable, Sendable {
	public let groupJID: String?
	public let participants: [HistorySyncPastParticipant]

	public init(groupJID: String?, participants: [HistorySyncPastParticipant]) {
		self.groupJID = groupJID
		self.participants = participants
	}
}

public struct HistorySyncPastParticipant: Equatable, Sendable {
	public let userJID: String?
	public let leaveReason: HistorySyncPastParticipantLeaveReason?
	public let leaveTimestamp: UInt64?

	public init(
		userJID: String?,
		leaveReason: HistorySyncPastParticipantLeaveReason?,
		leaveTimestamp: UInt64?
	) {
		self.userJID = userJID
		self.leaveReason = leaveReason
		self.leaveTimestamp = leaveTimestamp
	}
}

public enum HistorySyncPastParticipantLeaveReason: Equatable, Sendable {
	case left
	case removed
	case unrecognized(Int)
}

enum HistorySyncProcessor {
	static func process(_ item: Proto_HistorySync) -> MessagingHistorySet {
		var messages: [ReceivedMessage] = []
		var contacts: [HistorySyncContact] = []
		var chats: [HistorySyncChat] = []
		var lidPnMappings: [LIDMapping] = item.phoneNumberToLidMappings.compactMap { mapping in
			guard mapping.hasLidJid, mapping.hasPnJid else {
				return nil
			}
			return LIDMapping(pn: mapping.pnJid, lid: mapping.lidJid)
		}

		switch item.syncType {
		case .initialBootstrap, .recent, .full, .onDemand:
			for chat in item.conversations {
				contacts.append(HistorySyncContact(
					id: chat.id,
					name: firstNonEmpty(chat.hasDisplayName ? chat.displayName : nil, chat.hasName ? chat.name : nil, chat.hasUsername ? chat.username : nil),
					username: chat.hasUsername ? chat.username : nil,
					lid: chat.hasLidJid ? chat.lidJid : chat.hasAccountLid ? chat.accountLid : nil,
					phoneNumber: chat.hasPnJid ? chat.pnJid : nil,
					notify: nil,
					verifiedName: nil
				))

				if (chat.id.isLIDUserJID || chat.id.isHostedLIDUserJID), chat.hasPnJid {
					lidPnMappings.append(LIDMapping(pn: chat.pnJid, lid: chat.id))
				} else if (chat.id.isWhatsAppUserJID || chat.id.isHostedUserJID), chat.hasLidJid {
					lidPnMappings.append(LIDMapping(pn: chat.id, lid: chat.lidJid))
				} else if chat.id.isLIDUserJID || chat.id.isHostedLIDUserJID,
						  let phoneNumber = phoneNumberFromReceipts(in: chat.messages) {
					lidPnMappings.append(LIDMapping(pn: phoneNumber, lid: chat.id))
				}

				var latestMessage: ReceivedMessage?
				var lastMessageReceivedTimestamp: UInt64?
				for item in chat.messages where item.hasMessage {
					guard let message = ReceivedWebMessageInfoParser.parse(item.message) else {
						continue
					}
					messages.append(message)

					if latestMessage == nil {
						latestMessage = message
					}
					if message.fromMe == false, lastMessageReceivedTimestamp == nil {
						lastMessageReceivedTimestamp = message.timestamp
					}

					if item.message.messageStubType == .bizPrivacyModeToBsp || item.message.messageStubType == .bizPrivacyModeToFb,
					   let verifiedName = item.message.messageStubParameters.first {
						let id = firstNonEmpty(
							item.message.key.hasParticipant ? item.message.key.participant : nil,
							item.message.key.hasRemoteJid ? item.message.key.remoteJid : nil
						)
						if let id {
							contacts.append(HistorySyncContact(
								id: id,
								name: nil,
								username: nil,
								lid: nil,
								phoneNumber: nil,
								notify: nil,
								verifiedName: verifiedName
							))
						}
					}
				}

				chats.append(HistorySyncChat(
					id: chat.id,
					name: chat.hasName ? chat.name : nil,
					displayName: chat.hasDisplayName ? chat.displayName : nil,
					username: chat.hasUsername ? chat.username : nil,
					lid: chat.hasLidJid ? chat.lidJid : chat.hasAccountLid ? chat.accountLid : nil,
					phoneNumber: chat.hasPnJid ? chat.pnJid : nil,
					lastMessageReceivedTimestamp: lastMessageReceivedTimestamp,
					latestMessage: latestMessage
				))
			}
		case .pushName:
			contacts.append(contentsOf: item.pushnames.compactMap { pushName in
				guard pushName.hasID, pushName.hasPushname else {
					return nil
				}
				return HistorySyncContact(
					id: pushName.id,
					name: nil,
					username: nil,
					lid: nil,
					phoneNumber: nil,
					notify: pushName.pushname,
					verifiedName: nil
				)
			})
		case .initialStatusV3, .nonBlockingData, .UNRECOGNIZED:
			break
		}

		return MessagingHistorySet(
			chats: chats,
			contacts: contacts,
			messages: messages,
			lidPnMappings: lidPnMappings,
			pastParticipants: pastParticipants(item.pastParticipants),
			syncType: historySyncType(item.syncType),
			progress: item.hasProgress ? item.progress : nil
		)
	}

	private static func firstNonEmpty(_ values: String?...) -> String? {
		values.first { value in
			guard let value else {
				return false
			}
			return !value.isEmpty
		} ?? nil
	}

	private static func phoneNumberFromReceipts(in messages: [Proto_HistorySyncMsg]) -> String? {
		for item in messages where item.hasMessage {
			let message = item.message
			guard message.key.hasFromMe, message.key.fromMe else {
				continue
			}
			guard let userJID = message.userReceipt.first?.userJid,
				  userJID.isWhatsAppUserJID || userJID.isHostedUserJID else {
				continue
			}
			return userJID
		}
		return nil
	}

	private static func historySyncType(_ type: Proto_HistorySync.HistorySyncType) -> ReceivedHistorySyncType {
		switch type {
		case .initialBootstrap:
			.initialBootstrap
		case .initialStatusV3:
			.initialStatusV3
		case .full:
			.full
		case .recent:
			.recent
		case .pushName:
			.pushName
		case .nonBlockingData:
			.nonBlockingData
		case .onDemand:
			.onDemand
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	private static func pastParticipants(_ groups: [Proto_PastParticipants]) -> [HistorySyncPastParticipants] {
		groups.map { group in
			HistorySyncPastParticipants(
				groupJID: group.hasGroupJid ? group.groupJid : nil,
				participants: group.pastParticipants.map { participant in
					HistorySyncPastParticipant(
						userJID: participant.hasUserJid ? participant.userJid : nil,
						leaveReason: participant.hasLeaveReason ? leaveReason(participant.leaveReason) : nil,
						leaveTimestamp: participant.hasLeaveTs ? participant.leaveTs : nil
					)
				}
			)
		}
	}

	private static func leaveReason(
		_ reason: Proto_PastParticipant.LeaveReason
	) -> HistorySyncPastParticipantLeaveReason {
		switch reason {
		case .left:
			.left
		case .removed:
			.removed
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}
}
