import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward comment messages")
struct WhatsAppClientForwardCommentMessageTests {
	@Test("forwards received comment messages through the encrypted send path")
	func forwardsReceivedCommentMessagesThroughEncryptedSendPath() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .text("comment text"),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.targetMessageKey.remoteJid == "status@broadcast")
		#expect(message.commentMessage.targetMessageKey.id == "target-status")
		#expect(message.commentMessage.message.hasExtendedTextMessage)
		#expect(message.commentMessage.message.extendedTextMessage.text == "comment text")
		#expect(message.commentMessage.message.extendedTextMessage.contextInfo.isForwarded)
	}

	@Test("forwards received comment messages with location content")
	func forwardsReceivedCommentMessagesWithLocationContent() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .location(ReceivedLocationContent(
				latitude: -25.966213,
				longitude: 32.573174,
				name: "Maputo Central Market",
				address: "Av. 25 de Setembro",
				url: "https://maps.example/place",
				accuracyInMeters: 15,
				comment: "meet here",
				jpegThumbnail: Data([0x0a, 0x0b])
			)),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-location-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.message.hasLocationMessage)
		#expect(message.commentMessage.message.locationMessage.name == "Maputo Central Market")
		#expect(message.commentMessage.message.locationMessage.degreesLatitude == -25.966213)
		#expect(message.commentMessage.message.locationMessage.jpegThumbnail == Data([0x0a, 0x0b]))
	}

	@Test("forwards received comment messages with contact content")
	func forwardsReceivedCommentMessagesWithContactContent() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .contact(ReceivedContactContent(
				displayName: "Maria Silva",
				vcard: "BEGIN:VCARD\nFN:Maria Silva\nTEL:+258840000000\nEND:VCARD"
			)),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-contact-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.message.hasContactMessage)
		#expect(message.commentMessage.message.contactMessage.displayName == "Maria Silva")
		#expect(message.commentMessage.message.contactMessage.vcard.contains("+258840000000"))
	}

	@Test("forwards received comment messages with contacts content")
	func forwardsReceivedCommentMessagesWithContactsContent() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .contacts(ReceivedContactsContent(
				displayName: "2 contacts",
				contacts: [
					ReceivedContactContent(
						displayName: "Maria Silva",
						vcard: "BEGIN:VCARD\nFN:Maria Silva\nTEL:+258840000000\nEND:VCARD"
					),
					ReceivedContactContent(
						displayName: "Joao Machel",
						vcard: "BEGIN:VCARD\nFN:Joao Machel\nTEL:+258850000000\nEND:VCARD"
					)
				]
			)),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-contacts-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.message.hasContactsArrayMessage)
		#expect(message.commentMessage.message.contactsArrayMessage.displayName == "2 contacts")
		#expect(message.commentMessage.message.contactsArrayMessage.contacts.map(\.displayName) == ["Maria Silva", "Joao Machel"])
	}

	@Test("forwards received comment messages with event content")
	func forwardsReceivedCommentMessagesWithEventContent() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .event(ReceivedEventContent(
				name: "Swift Baileys meetup",
				description: "Protocol parity session",
				startTime: 1_700_100_000,
				endTime: 1_700_103_600,
				joinLink: "https://call.whatsapp.com/video/example",
				isCanceled: false,
				extraGuestsAllowed: true,
				isScheduledCall: true,
				location: ReceivedLocationContent(
					latitude: -25.966213,
					longitude: 32.56745,
					name: "Maputo Central",
					address: "Av. 25 de Setembro",
					url: "https://maps.example/event",
					accuracyInMeters: 8,
					comment: "front entrance",
					jpegThumbnail: Data([0x03, 0x04])
				)
			)),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-event-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.message.hasEventMessage)
		#expect(message.commentMessage.message.eventMessage.name == "Swift Baileys meetup")
		#expect(message.commentMessage.message.eventMessage.joinLink == "https://call.whatsapp.com/video/example")
		#expect(message.commentMessage.message.eventMessage.extraGuestsAllowed)
		#expect(message.commentMessage.message.eventMessage.location.name == "Maputo Central")
		#expect(message.commentMessage.message.eventMessage.location.jpegThumbnail == Data([0x03, 0x04]))
	}

	@Test("forwards received comment messages with group invite content")
	func forwardsReceivedCommentMessagesWithGroupInviteContent() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .groupInvite(ReceivedGroupInviteContent(
				groupJID: "120363000000000000@g.us",
				inviteCode: "ABCD1234",
				inviteExpiration: 1_700_010_000,
				groupName: "Swift Group",
				caption: "Join us",
				groupType: .parent,
				jpegThumbnail: Data([0x01, 0x02])
			)),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-group-invite-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.message.hasGroupInviteMessage)
		#expect(message.commentMessage.message.groupInviteMessage.groupJid == "120363000000000000@g.us")
		#expect(message.commentMessage.message.groupInviteMessage.inviteCode == "ABCD1234")
		#expect(message.commentMessage.message.groupInviteMessage.groupType == .parent)
		#expect(message.commentMessage.message.groupInviteMessage.jpegThumbnail == Data([0x01, 0x02]))
	}

	@Test("forwards received comment messages with request phone number content")
	func forwardsReceivedCommentMessagesWithRequestPhoneNumberContent() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .requestPhoneNumber(ReceivedRequestPhoneNumberContent()),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-request-phone-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.message.hasRequestPhoneNumberMessage)
	}

	@Test("forwards received comment messages with ephemeral setting content")
	func forwardsReceivedCommentMessagesWithEphemeralSettingContent() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .ephemeralSetting(ReceivedEphemeralSettingContent(
				expirationSeconds: 604_800,
				settingTimestampSeconds: 1_700_003_100,
				disappearingMode: ReceivedDisappearingModeContent(
					initiator: .initiatedByMe,
					trigger: .accountSetting,
					initiatorDeviceJID: "123.0@s.whatsapp.net",
					initiatedByMe: true
				)
			)),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-ephemeral-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.message.protocolMessage.type == .ephemeralSetting)
		#expect(message.commentMessage.message.protocolMessage.ephemeralExpiration == 604_800)
		#expect(message.commentMessage.message.protocolMessage.ephemeralSettingTimestamp == 1_700_003_100)
		#expect(message.commentMessage.message.protocolMessage.disappearingMode.initiator == .initiatedByMe)
		#expect(message.commentMessage.message.protocolMessage.disappearingMode.trigger == .accountSetting)
		#expect(message.commentMessage.message.protocolMessage.disappearingMode.initiatorDeviceJid == "123.0@s.whatsapp.net")
		#expect(message.commentMessage.message.protocolMessage.disappearingMode.initiatedByMe)
	}

	@Test("forwards received comment messages with limit sharing content")
	func forwardsReceivedCommentMessagesWithLimitSharingContent() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .limitSharing(ReceivedLimitSharingContent(
				sharingLimited: true,
				trigger: .unknownGroup,
				settingTimestampMilliseconds: 1_717_777_100,
				initiatedByMe: false
			)),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-limit-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.message.protocolMessage.type == .limitSharing)
		#expect(message.commentMessage.message.protocolMessage.limitSharing.sharingLimited)
		#expect(message.commentMessage.message.protocolMessage.limitSharing.trigger == .unknownGroup)
		#expect(message.commentMessage.message.protocolMessage.limitSharing.limitSharingSettingTimestamp == 1_717_777_100)
		#expect(!message.commentMessage.message.protocolMessage.limitSharing.initiatedByMe)
	}

	@Test("forwards received comment messages with group member label change content")
	func forwardsReceivedCommentMessagesWithGroupMemberLabelChangeContent() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .groupMemberLabelChange(ReceivedGroupMemberLabelChangeContent(
				label: "priority",
				labelTimestamp: 1_700_000_104
			)),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-member-label-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.message.protocolMessage.type == .groupMemberLabelChange)
		#expect(message.commentMessage.message.protocolMessage.memberLabel.label == "priority")
		#expect(message.commentMessage.message.protocolMessage.memberLabel.labelTimestamp == 1_700_000_104)
	}

	@Test("forwards received comment messages with shared phone number content")
	func forwardsReceivedCommentMessagesWithSharedPhoneNumberContent() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .phoneNumberShared(ReceivedPhoneNumberSharedContent()),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-shared-phone-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.message.hasProtocolMessage)
		#expect(message.commentMessage.message.protocolMessage.type == .sharePhoneNumber)
	}

	@Test("forwards received comment messages with scheduled call creation content")
	func forwardsReceivedCommentMessagesWithScheduledCallCreationContent() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .scheduledCallCreation(ReceivedScheduledCallCreationContent(
				scheduledTimestampMilliseconds: 1_700_200_000_000,
				callType: .video,
				title: "Weekly sync"
			)),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-scheduled-call-create-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.message.hasScheduledCallCreationMessage)
		#expect(message.commentMessage.message.scheduledCallCreationMessage.scheduledTimestampMs == 1_700_200_000_000)
		#expect(message.commentMessage.message.scheduledCallCreationMessage.callType == .video)
		#expect(message.commentMessage.message.scheduledCallCreationMessage.title == "Weekly sync")
	}

	@Test("forwards received comment messages with scheduled call edit content")
	func forwardsReceivedCommentMessagesWithScheduledCallEditContent() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .scheduledCallEdit(ReceivedScheduledCallEditContent(
				key: ReceivedMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "SCHEDULED_CALL_MESSAGE_ID",
					participant: "258840000000@s.whatsapp.net"
				),
				editType: .cancel
			)),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-scheduled-call-edit-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.message.hasScheduledCallEditMessage)
		#expect(message.commentMessage.message.scheduledCallEditMessage.key.id == "SCHEDULED_CALL_MESSAGE_ID")
		#expect(message.commentMessage.message.scheduledCallEditMessage.editType == .cancel)
	}

	@Test("forwards received comment messages with poll creation content")
	func forwardsReceivedCommentMessagesWithPollCreationContent() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .pollCreation(ReceivedPollCreationContent(
				name: "Best Baileys port?",
				options: [
					ReceivedPollOption(name: "Swift", hash: "hash-swift"),
					ReceivedPollOption(name: "TypeScript", hash: "hash-typescript")
				],
				selectableOptionsCount: 1,
				encryptedKey: Data([0x01, 0x02, 0x03]),
				contentType: .text,
				pollType: .quiz,
				correctAnswer: ReceivedPollOption(name: "Swift", hash: "hash-swift")
			)),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-poll-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.message.hasPollCreationMessageV3)
		#expect(message.commentMessage.message.pollCreationMessageV3.name == "Best Baileys port?")
		#expect(message.commentMessage.message.pollCreationMessageV3.options.map(\.optionName) == ["Swift", "TypeScript"])
		#expect(message.commentMessage.message.pollCreationMessageV3.options.map(\.optionHash) == ["hash-swift", "hash-typescript"])
		#expect(message.commentMessage.message.pollCreationMessageV3.encKey == Data([0x01, 0x02, 0x03]))
		#expect(message.commentMessage.message.pollCreationMessageV3.pollType == .quiz)
		#expect(message.commentMessage.message.pollCreationMessageV3.correctAnswer.optionName == "Swift")
	}

	@Test("forwards received comment messages with poll update content")
	func forwardsReceivedCommentMessagesWithPollUpdateContent() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .pollUpdate(ReceivedPollUpdateContent(
				pollCreationMessageKey: ReceivedMessageKey(
					remoteJID: "258840000000@s.whatsapp.net",
					fromMe: false,
					id: "3EB0POLL",
					participant: "258841111111@s.whatsapp.net"
				),
				encryptedPayload: Data([0x01, 0x02, 0x03]),
				encryptedIV: Data([0x04, 0x05, 0x06]),
				senderTimestampMilliseconds: 1_700_002_000_000
			)),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-poll-update-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.message.hasPollUpdateMessage)
		#expect(message.commentMessage.message.pollUpdateMessage.pollCreationMessageKey.id == "3EB0POLL")
		#expect(message.commentMessage.message.pollUpdateMessage.vote.encPayload == Data([0x01, 0x02, 0x03]))
		#expect(message.commentMessage.message.pollUpdateMessage.vote.encIv == Data([0x04, 0x05, 0x06]))
		#expect(message.commentMessage.message.pollUpdateMessage.senderTimestampMs == 1_700_002_000_000)
	}

	@Test("forwards received comment messages with poll result snapshot content")
	func forwardsReceivedCommentMessagesWithPollResultSnapshotContent() async throws {
		let message = try await forwardedMessage(content: .comment(ReceivedCommentContent(
			content: .pollResultSnapshot(ReceivedPollResultSnapshotContent(
				name: "Launch window",
				votes: [ReceivedPollResultVote(optionName: "Morning", voteCount: 7)],
				pollType: .quiz
			)),
			targetMessageKey: ReceivedMessageKey(
				remoteJID: "status@broadcast",
				fromMe: false,
				id: "target-poll-result-status",
				participant: nil
			)
		)))

		#expect(message.hasCommentMessage)
		#expect(message.commentMessage.message.hasPollResultSnapshotMessage)
		#expect(message.commentMessage.message.pollResultSnapshotMessage.name == "Launch window")
		#expect(message.commentMessage.message.pollResultSnapshotMessage.pollVotes.map(\.optionName) == ["Morning"])
		#expect(message.commentMessage.message.pollResultSnapshotMessage.pollVotes.map(\.optionVoteCount) == [7])
		#expect(message.commentMessage.message.pollResultSnapshotMessage.pollType == .quiz)
	}

	private func forwardedMessage(content: ReceivedMessageContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x2b]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "COMMENT1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDEDCOMMENT"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
