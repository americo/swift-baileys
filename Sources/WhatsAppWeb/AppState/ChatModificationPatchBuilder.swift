enum ChatModificationPatchType: String, Equatable, Sendable {
	case criticalBlock = "critical_block"
	case criticalUnblockLow = "critical_unblock_low"
	case regular
	case regularHigh = "regular_high"
	case regularLow = "regular_low"
}

enum ChatModificationPatchOperation: Equatable, Sendable {
	case remove
	case set
}

struct ChatModificationPatch: Equatable, Sendable {
	let syncAction: Proto_SyncActionValue
	let index: [String]
	let type: ChatModificationPatchType
	let apiVersion: UInt32
	let operation: ChatModificationPatchOperation

	init(
		syncAction: Proto_SyncActionValue,
		index: [String],
		type: ChatModificationPatchType,
		apiVersion: UInt32,
		operation: ChatModificationPatchOperation
	) {
		self.syncAction = syncAction
		self.index = index
		self.type = type
		self.apiVersion = apiVersion
		self.operation = operation
	}
}

struct ChatModificationContact: Equatable, Sendable {
	let fullName: String?
	let firstName: String?
	let lidJid: String?
	let saveOnPrimaryAddressbook: Bool?
	let pnJid: String?
	let username: String?

	init(
		fullName: String? = nil,
		firstName: String? = nil,
		lidJid: String? = nil,
		saveOnPrimaryAddressbook: Bool? = nil,
		pnJid: String? = nil,
		username: String? = nil
	) {
		self.fullName = fullName
		self.firstName = firstName
		self.lidJid = lidJid
		self.saveOnPrimaryAddressbook = saveOnPrimaryAddressbook
		self.pnJid = pnJid
		self.username = username
	}
}

enum ChatModification: Equatable, Sendable {
	case mute(jid: String, muteEndTimestamp: Int64?)
	case archive(jid: String, archived: Bool, messageRange: Proto_SyncActionValue.SyncActionMessageRange)
	case markRead(jid: String, read: Bool, messageRange: Proto_SyncActionValue.SyncActionMessageRange)
	case pushNameSetting(String)
	case disableLinkPreviews(isPreviewsDisabled: Bool)
	case clear(jid: String, messageRange: Proto_SyncActionValue.SyncActionMessageRange)
	case pin(jid: String, pinned: Bool)
	case contact(jid: String, contact: ChatModificationContact?)
	case star(jid: String, messageID: String, fromMe: Bool, starred: Bool)
	case deleteChat(jid: String, messageRange: Proto_SyncActionValue.SyncActionMessageRange)
	case deleteForMe(jid: String, messageID: String, fromMe: Bool, timestamp: Int64, deleteMedia: Bool)
	case quickReply(timestamp: String, shortcut: String, message: String, deleted: Bool)
	case labelEdit(id: String, name: String?, color: Int32?, predefinedID: Int32?, deleted: Bool?)
	case chatLabel(jid: String, labelID: String, labeled: Bool)
	case messageLabel(jid: String, messageID: String, labelID: String, labeled: Bool)
}

enum ChatModificationPatchBuilder {
	static func patch(for modification: ChatModification) -> ChatModificationPatch {
		switch modification {
		case .mute(let jid, let muteEndTimestamp):
			var mute = Proto_SyncActionValue.MuteAction()
			mute.muted = muteEndTimestamp != nil
			if let muteEndTimestamp {
				mute.muteEndTimestamp = muteEndTimestamp
			}
			var action = Proto_SyncActionValue()
			action.muteAction = mute
			return ChatModificationPatch(
				syncAction: action,
				index: ["mute", jid],
				type: .regularHigh,
				apiVersion: 2,
				operation: .set
			)
		case .archive(let jid, let archived, let messageRange):
			var archive = Proto_SyncActionValue.ArchiveChatAction()
			archive.archived = archived
			archive.messageRange = messageRange
			var action = Proto_SyncActionValue()
			action.archiveChatAction = archive
			return ChatModificationPatch(
				syncAction: action,
				index: ["archive", jid],
				type: .regularLow,
				apiVersion: 3,
				operation: .set
			)
		case .markRead(let jid, let read, let messageRange):
			var markRead = Proto_SyncActionValue.MarkChatAsReadAction()
			markRead.read = read
			markRead.messageRange = messageRange
			var action = Proto_SyncActionValue()
			action.markChatAsReadAction = markRead
			return ChatModificationPatch(
				syncAction: action,
				index: ["markChatAsRead", jid],
				type: .regularLow,
				apiVersion: 3,
				operation: .set
			)
		case .pushNameSetting(let name):
			var setting = Proto_SyncActionValue.PushNameSetting()
			setting.name = name
			var action = Proto_SyncActionValue()
			action.pushNameSetting = setting
			return ChatModificationPatch(
				syncAction: action,
				index: ["setting_pushName"],
				type: .criticalBlock,
				apiVersion: 1,
				operation: .set
			)
		case .disableLinkPreviews(let isPreviewsDisabled):
			var setting = Proto_SyncActionValue.PrivacySettingDisableLinkPreviewsAction()
			setting.isPreviewsDisabled = isPreviewsDisabled
			var action = Proto_SyncActionValue()
			action.privacySettingDisableLinkPreviewsAction = setting
			return ChatModificationPatch(
				syncAction: action,
				index: ["setting_disableLinkPreviews"],
				type: .regular,
				apiVersion: 8,
				operation: .set
			)
		case .clear(let jid, let messageRange):
			var clear = Proto_SyncActionValue.ClearChatAction()
			clear.messageRange = messageRange
			var action = Proto_SyncActionValue()
			action.clearChatAction_p = clear
			return ChatModificationPatch(
				syncAction: action,
				index: ["clearChat", jid, "1", "0"],
				type: .regularHigh,
				apiVersion: 6,
				operation: .set
			)
		case .pin(let jid, let pinned):
			var pin = Proto_SyncActionValue.PinAction()
			pin.pinned = pinned
			var action = Proto_SyncActionValue()
			action.pinAction = pin
			return ChatModificationPatch(
				syncAction: action,
				index: ["pin_v1", jid],
				type: .regularLow,
				apiVersion: 5,
				operation: .set
			)
		case .contact(let jid, let contact):
			var contactAction = Proto_SyncActionValue.ContactAction()
			if let contact {
				if let fullName = contact.fullName {
					contactAction.fullName = fullName
				}
				if let firstName = contact.firstName {
					contactAction.firstName = firstName
				}
				if let lidJid = contact.lidJid {
					contactAction.lidJid = lidJid
				}
				if let saveOnPrimaryAddressbook = contact.saveOnPrimaryAddressbook {
					contactAction.saveOnPrimaryAddressbook = saveOnPrimaryAddressbook
				}
				if let pnJid = contact.pnJid {
					contactAction.pnJid = pnJid
				}
				if let username = contact.username {
					contactAction.username = username
				}
			}
			var action = Proto_SyncActionValue()
			action.contactAction = contactAction
			return ChatModificationPatch(
				syncAction: action,
				index: ["contact", jid],
				type: .criticalUnblockLow,
				apiVersion: 2,
				operation: contact == nil ? .remove : .set
			)
		case .star(let jid, let messageID, let fromMe, let starred):
			var star = Proto_SyncActionValue.StarAction()
			star.starred = starred
			var action = Proto_SyncActionValue()
			action.starAction = star
			return ChatModificationPatch(
				syncAction: action,
				index: ["star", jid, messageID, fromMe ? "1" : "0", "0"],
				type: .regularLow,
				apiVersion: 2,
				operation: .set
			)
		case .deleteChat(let jid, let messageRange):
			var delete = Proto_SyncActionValue.DeleteChatAction()
			delete.messageRange = messageRange
			var action = Proto_SyncActionValue()
			action.deleteChatAction = delete
			return ChatModificationPatch(
				syncAction: action,
				index: ["deleteChat", jid, "1"],
				type: .regularHigh,
				apiVersion: 6,
				operation: .set
			)
		case .deleteForMe(let jid, let messageID, let fromMe, let timestamp, let deleteMedia):
			var delete = Proto_SyncActionValue.DeleteMessageForMeAction()
			delete.deleteMedia = deleteMedia
			delete.messageTimestamp = timestamp
			var action = Proto_SyncActionValue()
			action.deleteMessageForMeAction = delete
			return ChatModificationPatch(
				syncAction: action,
				index: ["deleteMessageForMe", jid, messageID, fromMe ? "1" : "0", "0"],
				type: .regularHigh,
				apiVersion: 3,
				operation: .set
			)
		case .quickReply(let timestamp, let shortcut, let message, let deleted):
			var quickReply = Proto_SyncActionValue.QuickReplyAction()
			quickReply.count = 0
			quickReply.deleted = deleted
			quickReply.keywords = []
			quickReply.message = message
			quickReply.shortcut = shortcut
			var action = Proto_SyncActionValue()
			action.quickReplyAction = quickReply
			return ChatModificationPatch(
				syncAction: action,
				index: ["quick_reply", timestamp],
				type: .regular,
				apiVersion: 2,
				operation: .set
			)
		case .labelEdit(let id, let name, let color, let predefinedID, let deleted):
			var edit = Proto_SyncActionValue.LabelEditAction()
			if let name {
				edit.name = name
			}
			if let color {
				edit.color = color
			}
			if let predefinedID {
				edit.predefinedID = predefinedID
			}
			if let deleted {
				edit.deleted = deleted
			}
			var action = Proto_SyncActionValue()
			action.labelEditAction = edit
			return ChatModificationPatch(
				syncAction: action,
				index: ["label_edit", id],
				type: .regular,
				apiVersion: 3,
				operation: .set
			)
		case .chatLabel(let jid, let labelID, let labeled):
			var association = Proto_SyncActionValue.LabelAssociationAction()
			association.labeled = labeled
			var action = Proto_SyncActionValue()
			action.labelAssociationAction = association
			return ChatModificationPatch(
				syncAction: action,
				index: ["label_jid", labelID, jid],
				type: .regular,
				apiVersion: 3,
				operation: .set
			)
		case .messageLabel(let jid, let messageID, let labelID, let labeled):
			var association = Proto_SyncActionValue.LabelAssociationAction()
			association.labeled = labeled
			var action = Proto_SyncActionValue()
			action.labelAssociationAction = association
			return ChatModificationPatch(
				syncAction: action,
				index: ["label_message", labelID, jid, messageID, "0", "0"],
				type: .regular,
				apiVersion: 3,
				operation: .set
			)
		}
	}
}
