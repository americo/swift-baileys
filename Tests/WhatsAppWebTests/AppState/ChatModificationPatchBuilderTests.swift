import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Chat modification patch builder")
struct ChatModificationPatchBuilderTests {
	@Test("builds mute patch metadata")
	func buildsMutePatchMetadata() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .mute(
			jid: "123@s.whatsapp.net",
			muteEndTimestamp: 60
		))

		#expect(patch.index == ["mute", "123@s.whatsapp.net"])
		#expect(patch.type == .regularHigh)
		#expect(patch.apiVersion == 2)
		#expect(patch.operation == .set)
		#expect(patch.syncAction.hasMuteAction)
		#expect(patch.syncAction.muteAction.muted)
		#expect(patch.syncAction.muteAction.muteEndTimestamp == 60)
		#expect(try patch.syncAction.serializedData() == Data([0x22, 0x04, 0x08, 0x01, 0x10, 0x3c]))
	}

	@Test("builds archive patch metadata")
	func buildsArchivePatchMetadata() throws {
		var range = Proto_SyncActionValue.SyncActionMessageRange()
		range.lastMessageTimestamp = 60

		let patch = ChatModificationPatchBuilder.patch(for: .archive(
			jid: "123@s.whatsapp.net",
			archived: true,
			messageRange: range
		))

		#expect(patch.index == ["archive", "123@s.whatsapp.net"])
		#expect(patch.type == .regularLow)
		#expect(patch.apiVersion == 3)
		#expect(patch.operation == .set)
		#expect(patch.syncAction.hasArchiveChatAction)
		#expect(patch.syncAction.archiveChatAction.archived)
		#expect(patch.syncAction.archiveChatAction.messageRange.lastMessageTimestamp == 60)
		#expect(try patch.syncAction.serializedData() == Data([
			0x8a, 0x01, 0x06,
			0x08, 0x01,
			0x12, 0x02, 0x08, 0x3c
		]))
	}

	@Test("builds mark-read patch metadata")
	func buildsMarkReadPatchMetadata() throws {
		var range = Proto_SyncActionValue.SyncActionMessageRange()
		range.lastMessageTimestamp = 60

		let patch = ChatModificationPatchBuilder.patch(for: .markRead(
			jid: "123@s.whatsapp.net",
			read: false,
			messageRange: range
		))

		#expect(patch.index == ["markChatAsRead", "123@s.whatsapp.net"])
		#expect(patch.type == .regularLow)
		#expect(patch.apiVersion == 3)
		#expect(patch.operation == .set)
		#expect(patch.syncAction.hasMarkChatAsReadAction)
		#expect(!patch.syncAction.markChatAsReadAction.read)
		#expect(patch.syncAction.markChatAsReadAction.messageRange.lastMessageTimestamp == 60)
		#expect(try patch.syncAction.serializedData() == Data([
			0xa2, 0x01, 0x06,
			0x08, 0x00,
			0x12, 0x02, 0x08, 0x3c
		]))
	}

	@Test("builds push-name setting patch metadata")
	func buildsPushNameSettingPatchMetadata() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .pushNameSetting("Americo"))

		#expect(patch.index == ["setting_pushName"])
		#expect(patch.type == .criticalBlock)
		#expect(patch.apiVersion == 1)
		#expect(patch.operation == .set)
		#expect(patch.syncAction.hasPushNameSetting)
		#expect(patch.syncAction.pushNameSetting.name == "Americo")
		#expect(try patch.syncAction.serializedData() == Data([0x3a, 0x09, 0x0a, 0x07, 0x41, 0x6d, 0x65, 0x72, 0x69, 0x63, 0x6f]))
	}

	@Test("builds disable-link-previews setting patch metadata")
	func buildsDisableLinkPreviewsSettingPatchMetadata() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .disableLinkPreviews(isPreviewsDisabled: true))

		#expect(patch.index == ["setting_disableLinkPreviews"])
		#expect(patch.type == .regular)
		#expect(patch.apiVersion == 8)
		#expect(patch.operation == .set)
		#expect(patch.syncAction.hasPrivacySettingDisableLinkPreviewsAction)
		#expect(patch.syncAction.privacySettingDisableLinkPreviewsAction.isPreviewsDisabled)
		#expect(try patch.syncAction.serializedData() == Data([0xaa, 0x03, 0x02, 0x08, 0x01]))
	}

	@Test("builds clear-chat patch metadata")
	func buildsClearChatPatchMetadata() throws {
		var range = Proto_SyncActionValue.SyncActionMessageRange()
		range.lastMessageTimestamp = 60

		let patch = ChatModificationPatchBuilder.patch(for: .clear(
			jid: "123@s.whatsapp.net",
			messageRange: range
		))

		#expect(patch.index == ["clearChat", "123@s.whatsapp.net", "1", "0"])
		#expect(patch.type == .regularHigh)
		#expect(patch.apiVersion == 6)
		#expect(patch.operation == .set)
		#expect(patch.syncAction.hasClearChatAction_p)
		#expect(patch.syncAction.clearChatAction_p.messageRange.lastMessageTimestamp == 60)
		#expect(try patch.syncAction.serializedData() == Data([
			0xaa, 0x01, 0x04,
			0x0a, 0x02, 0x08, 0x3c
		]))
	}

	@Test("builds pin patch metadata")
	func buildsPinPatchMetadata() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .pin(
			jid: "123@s.whatsapp.net",
			pinned: true
		))

		#expect(patch.index == ["pin_v1", "123@s.whatsapp.net"])
		#expect(patch.type == .regularLow)
		#expect(patch.apiVersion == 5)
		#expect(patch.operation == .set)
		#expect(patch.syncAction.hasPinAction)
		#expect(patch.syncAction.pinAction.pinned)
		#expect(try patch.syncAction.serializedData() == Data([0x2a, 0x02, 0x08, 0x01]))
	}

	@Test("builds contact set patch metadata")
	func buildsContactSetPatchMetadata() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .contact(
			jid: "123@s.whatsapp.net",
			contact: ChatModificationContact(
				fullName: "Americo Junior",
				firstName: "Americo",
				lidJid: "123@lid",
				saveOnPrimaryAddressbook: true,
				pnJid: "123@s.whatsapp.net",
				username: "americo"
			)
		))

		#expect(patch.index == ["contact", "123@s.whatsapp.net"])
		#expect(patch.type == .criticalUnblockLow)
		#expect(patch.apiVersion == 2)
		#expect(patch.operation == .set)
		#expect(patch.syncAction.hasContactAction)
		#expect(patch.syncAction.contactAction.fullName == "Americo Junior")
		#expect(patch.syncAction.contactAction.firstName == "Americo")
		#expect(patch.syncAction.contactAction.lidJid == "123@lid")
		#expect(patch.syncAction.contactAction.saveOnPrimaryAddressbook)
		#expect(patch.syncAction.contactAction.pnJid == "123@s.whatsapp.net")
		#expect(patch.syncAction.contactAction.username == "americo")
		#expect(try patch.syncAction.serializedData() == Data([
			0x1a, 0x41,
			0x0a, 0x0e, 0x41, 0x6d, 0x65, 0x72, 0x69, 0x63, 0x6f, 0x20, 0x4a, 0x75, 0x6e, 0x69, 0x6f, 0x72,
			0x12, 0x07, 0x41, 0x6d, 0x65, 0x72, 0x69, 0x63, 0x6f,
			0x1a, 0x07, 0x31, 0x32, 0x33, 0x40, 0x6c, 0x69, 0x64,
			0x20, 0x01,
			0x2a, 0x12, 0x31, 0x32, 0x33, 0x40, 0x73, 0x2e, 0x77, 0x68, 0x61, 0x74, 0x73, 0x61, 0x70, 0x70, 0x2e, 0x6e, 0x65, 0x74,
			0x32, 0x07, 0x61, 0x6d, 0x65, 0x72, 0x69, 0x63, 0x6f
		]))
	}

	@Test("builds contact remove patch metadata")
	func buildsContactRemovePatchMetadata() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .contact(
			jid: "123@s.whatsapp.net",
			contact: nil
		))

		#expect(patch.index == ["contact", "123@s.whatsapp.net"])
		#expect(patch.type == .criticalUnblockLow)
		#expect(patch.apiVersion == 2)
		#expect(patch.operation == .remove)
		#expect(patch.syncAction.hasContactAction)
		#expect(try patch.syncAction.serializedData() == Data([0x1a, 0x00]))
	}

	@Test("builds star patch metadata")
	func buildsStarPatchMetadata() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .star(
			jid: "123@s.whatsapp.net",
			messageID: "3EB0STAR",
			fromMe: true,
			starred: true
		))

		#expect(patch.index == ["star", "123@s.whatsapp.net", "3EB0STAR", "1", "0"])
		#expect(patch.type == .regularLow)
		#expect(patch.apiVersion == 2)
		#expect(patch.operation == .set)
		#expect(patch.syncAction.hasStarAction)
		#expect(patch.syncAction.starAction.starred)
		#expect(try patch.syncAction.serializedData() == Data([0x12, 0x02, 0x08, 0x01]))
	}

	@Test("builds delete-chat patch metadata")
	func buildsDeleteChatPatchMetadata() throws {
		var range = Proto_SyncActionValue.SyncActionMessageRange()
		range.lastMessageTimestamp = 60

		let patch = ChatModificationPatchBuilder.patch(for: .deleteChat(
			jid: "123@s.whatsapp.net",
			messageRange: range
		))

		#expect(patch.index == ["deleteChat", "123@s.whatsapp.net", "1"])
		#expect(patch.type == .regularHigh)
		#expect(patch.apiVersion == 6)
		#expect(patch.operation == .set)
		#expect(patch.syncAction.hasDeleteChatAction)
		#expect(patch.syncAction.deleteChatAction.messageRange.lastMessageTimestamp == 60)
		#expect(try patch.syncAction.serializedData() == Data([
			0xb2, 0x01, 0x04,
			0x0a, 0x02, 0x08, 0x3c
		]))
	}

	@Test("builds delete-for-me patch metadata")
	func buildsDeleteForMePatchMetadata() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .deleteForMe(
			jid: "123@s.whatsapp.net",
			messageID: "3EB0DELETE",
			fromMe: false,
			timestamp: 60,
			deleteMedia: true
		))

		#expect(patch.index == ["deleteMessageForMe", "123@s.whatsapp.net", "3EB0DELETE", "0", "0"])
		#expect(patch.type == .regularHigh)
		#expect(patch.apiVersion == 3)
		#expect(patch.operation == .set)
		#expect(patch.syncAction.hasDeleteMessageForMeAction)
		#expect(patch.syncAction.deleteMessageForMeAction.deleteMedia)
		#expect(patch.syncAction.deleteMessageForMeAction.messageTimestamp == 60)
		#expect(try patch.syncAction.serializedData() == Data([0x92, 0x01, 0x04, 0x08, 0x01, 0x10, 0x3c]))
	}

	@Test("builds quick-reply patch metadata")
	func buildsQuickReplyPatchMetadata() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .quickReply(
			timestamp: "1718000000",
			shortcut: "/hours",
			message: "We are open from 8 to 17",
			deleted: false
		))

		#expect(patch.index == ["quick_reply", "1718000000"])
		#expect(patch.type == .regular)
		#expect(patch.apiVersion == 2)
		#expect(patch.operation == .set)
		#expect(patch.syncAction.hasQuickReplyAction)
		#expect(patch.syncAction.quickReplyAction.shortcut == "/hours")
		#expect(patch.syncAction.quickReplyAction.message == "We are open from 8 to 17")
		#expect(!patch.syncAction.quickReplyAction.deleted)
		#expect(try patch.syncAction.serializedData() == Data([
			0x42, 0x26,
			0x0a, 0x06, 0x2f, 0x68, 0x6f, 0x75, 0x72, 0x73,
			0x12, 0x18, 0x57, 0x65, 0x20, 0x61, 0x72, 0x65, 0x20, 0x6f, 0x70, 0x65, 0x6e, 0x20,
			0x66, 0x72, 0x6f, 0x6d, 0x20, 0x38, 0x20, 0x74, 0x6f, 0x20, 0x31, 0x37,
			0x20, 0x00,
			0x28, 0x00
		]))
	}

	@Test("builds label-edit patch metadata")
	func buildsLabelEditPatchMetadata() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .labelEdit(
			id: "label-1",
			name: "Urgent",
			color: 5,
			predefinedID: 7,
			deleted: false
		))

		#expect(patch.index == ["label_edit", "label-1"])
		#expect(patch.type == .regular)
		#expect(patch.apiVersion == 3)
		#expect(patch.operation == .set)
		#expect(patch.syncAction.hasLabelEditAction)
		#expect(patch.syncAction.labelEditAction.name == "Urgent")
		#expect(patch.syncAction.labelEditAction.color == 5)
		#expect(patch.syncAction.labelEditAction.predefinedID == 7)
		#expect(!patch.syncAction.labelEditAction.deleted)
		#expect(try patch.syncAction.serializedData() == Data([
			0x72, 0x0e,
			0x0a, 0x06, 0x55, 0x72, 0x67, 0x65, 0x6e, 0x74,
			0x10, 0x05,
			0x18, 0x07,
			0x20, 0x00
		]))
	}

	@Test("builds chat label association patch metadata")
	func buildsChatLabelAssociationPatchMetadata() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .chatLabel(
			jid: "123@s.whatsapp.net",
			labelID: "label-1",
			labeled: true
		))

		#expect(patch.index == ["label_jid", "label-1", "123@s.whatsapp.net"])
		#expect(patch.type == .regular)
		#expect(patch.apiVersion == 3)
		#expect(patch.operation == .set)
		#expect(patch.syncAction.hasLabelAssociationAction)
		#expect(patch.syncAction.labelAssociationAction.labeled)
		#expect(try patch.syncAction.serializedData() == Data([0x7a, 0x02, 0x08, 0x01]))
	}

	@Test("builds message label association patch metadata")
	func buildsMessageLabelAssociationPatchMetadata() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .messageLabel(
			jid: "123@s.whatsapp.net",
			messageID: "3EB0LABEL",
			labelID: "label-1",
			labeled: false
		))

		#expect(patch.index == ["label_message", "label-1", "123@s.whatsapp.net", "3EB0LABEL", "0", "0"])
		#expect(patch.type == .regular)
		#expect(patch.apiVersion == 3)
		#expect(patch.operation == .set)
		#expect(patch.syncAction.hasLabelAssociationAction)
		#expect(!patch.syncAction.labelAssociationAction.labeled)
		#expect(try patch.syncAction.serializedData() == Data([0x7a, 0x02, 0x08, 0x00]))
	}
}
