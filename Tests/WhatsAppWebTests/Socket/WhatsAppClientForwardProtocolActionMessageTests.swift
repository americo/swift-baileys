import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward protocol action messages")
struct WhatsAppClientForwardProtocolActionMessageTests {
	@Test("forwards received revoked and edited messages through the encrypted send path")
	func forwardsReceivedRevokedAndEditedMessagesThroughEncryptedSendPath() async throws {
		let key = ReceivedMessageKey(
			remoteJID: "258840000000@s.whatsapp.net",
			fromMe: true,
			id: "3EB0REVOKED",
			participant: nil
		)
		let revokedMessage = try await forwardedMessage(content: .messageRevoked(ReceivedMessageRevokedContent(
			key: key,
			timestampMilliseconds: 1_700_001_000_000
		)))

		#expect(revokedMessage.hasProtocolMessage)
		#expect(revokedMessage.protocolMessage.type == .revoke)
		#expect(revokedMessage.protocolMessage.key.id == "3EB0REVOKED")
		#expect(revokedMessage.protocolMessage.timestampMs == 1_700_001_000_000)

		let editedMessage = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITED",
				participant: nil
			),
			content: .text("edited text"),
			timestampMilliseconds: 1_700_001_111_000
		)))

		#expect(editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.type == .messageEdit)
		#expect(editedMessage.protocolMessage.key.id == "3EB0EDITED")
		#expect(editedMessage.protocolMessage.timestampMs == 1_700_001_111_000)
		#expect(editedMessage.protocolMessage.editedMessage.extendedTextMessage.text == "edited text")
		#expect(editedMessage.protocolMessage.editedMessage.extendedTextMessage.contextInfo.isForwarded)
	}

	@Test("forwards received edited messages with location content")
	func forwardsReceivedEditedMessagesWithLocationContent() async throws {
		let editedMessage = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITEDLOCATION",
				participant: nil
			),
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
			timestampMilliseconds: 1_700_001_222_000
		)))

		#expect(editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.type == .messageEdit)
		#expect(editedMessage.protocolMessage.editedMessage.hasLocationMessage)
		#expect(editedMessage.protocolMessage.editedMessage.locationMessage.name == "Maputo Central Market")
		#expect(editedMessage.protocolMessage.editedMessage.locationMessage.degreesLongitude == 32.573174)
		#expect(editedMessage.protocolMessage.editedMessage.locationMessage.jpegThumbnail == Data([0x0a, 0x0b]))
	}

	@Test("forwards received edited messages with live location content")
	func forwardsReceivedEditedMessagesWithLiveLocationContent() async throws {
		let editedMessage = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITEDLIVELOCATION",
				participant: nil
			),
			content: .liveLocation(ReceivedLiveLocationContent(
				latitude: -25.965331,
				longitude: 32.589245,
				accuracyInMeters: 8,
				speedInMetersPerSecond: 4.5,
				degreesClockwiseFromMagneticNorth: 91,
				caption: "on my way",
				sequenceNumber: 42,
				timeOffsetSeconds: 120,
				jpegThumbnail: Data([0x0c, 0x0d])
			)),
			timestampMilliseconds: 1_700_001_333_000
		)))

		#expect(editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.editedMessage.hasLiveLocationMessage)
		#expect(editedMessage.protocolMessage.editedMessage.liveLocationMessage.caption == "on my way")
		#expect(editedMessage.protocolMessage.editedMessage.liveLocationMessage.sequenceNumber == 42)
		#expect(editedMessage.protocolMessage.editedMessage.liveLocationMessage.jpegThumbnail == Data([0x0c, 0x0d]))
	}

	@Test("forwards received edited messages with contacts content")
	func forwardsReceivedEditedMessagesWithContactsContent() async throws {
		let editedMessage = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITEDCONTACTS",
				participant: nil
			),
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
			timestampMilliseconds: 1_700_001_444_000
		)))

		#expect(editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.editedMessage.hasContactsArrayMessage)
		#expect(editedMessage.protocolMessage.editedMessage.contactsArrayMessage.displayName == "2 contacts")
		#expect(editedMessage.protocolMessage.editedMessage.contactsArrayMessage.contacts.map(\.displayName) == ["Maria Silva", "Joao Machel"])
	}

	@Test("forwards received edited messages with event content")
	func forwardsReceivedEditedMessagesWithEventContent() async throws {
		let editedMessage = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITEDEVENT",
				participant: nil
			),
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
			timestampMilliseconds: 1_700_001_555_000
		)))

		#expect(editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.type == .messageEdit)
		#expect(editedMessage.protocolMessage.editedMessage.hasEventMessage)
		#expect(editedMessage.protocolMessage.editedMessage.eventMessage.name == "Swift Baileys meetup")
		#expect(editedMessage.protocolMessage.editedMessage.eventMessage.joinLink == "https://call.whatsapp.com/video/example")
		#expect(editedMessage.protocolMessage.editedMessage.eventMessage.extraGuestsAllowed)
		#expect(editedMessage.protocolMessage.editedMessage.eventMessage.location.name == "Maputo Central")
		#expect(editedMessage.protocolMessage.editedMessage.eventMessage.location.jpegThumbnail == Data([0x03, 0x04]))
	}

	@Test("forwards received edited messages with group invite content")
	func forwardsReceivedEditedMessagesWithGroupInviteContent() async throws {
		let editedMessage = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITEDGROUPINVITE",
				participant: nil
			),
			content: .groupInvite(ReceivedGroupInviteContent(
				groupJID: "120363000000000000@g.us",
				inviteCode: "ABCD1234",
				inviteExpiration: 1_700_010_000,
				groupName: "Swift Group",
				caption: "Join us",
				groupType: .parent,
				jpegThumbnail: Data([0x01, 0x02])
			)),
			timestampMilliseconds: 1_700_001_666_000
		)))

		#expect(editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.type == .messageEdit)
		#expect(editedMessage.protocolMessage.editedMessage.hasGroupInviteMessage)
		#expect(editedMessage.protocolMessage.editedMessage.groupInviteMessage.groupJid == "120363000000000000@g.us")
		#expect(editedMessage.protocolMessage.editedMessage.groupInviteMessage.inviteCode == "ABCD1234")
		#expect(editedMessage.protocolMessage.editedMessage.groupInviteMessage.groupType == .parent)
		#expect(editedMessage.protocolMessage.editedMessage.groupInviteMessage.jpegThumbnail == Data([0x01, 0x02]))
	}

	@Test("forwards received edited messages with request phone number content")
	func forwardsReceivedEditedMessagesWithRequestPhoneNumberContent() async throws {
		let editedMessage = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITEDREQUESTPHONE",
				participant: nil
			),
			content: .requestPhoneNumber(ReceivedRequestPhoneNumberContent()),
			timestampMilliseconds: 1_700_001_777_000
		)))

		#expect(editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.type == .messageEdit)
		#expect(editedMessage.protocolMessage.editedMessage.hasRequestPhoneNumberMessage)
	}

	@Test("forwards received edited messages with ephemeral setting content")
	func forwardsReceivedEditedMessagesWithEphemeralSettingContent() async throws {
		let editedMessage = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITEDEPHEMERAL",
				participant: nil
			),
			content: .ephemeralSetting(ReceivedEphemeralSettingContent(
				expirationSeconds: 604_800,
				settingTimestampSeconds: 1_700_003_200,
				disappearingMode: ReceivedDisappearingModeContent(
					initiator: .businessUpgradeFBHosting,
					trigger: .bizSupportsFBHosting,
					initiatorDeviceJID: "258840000000.0@s.whatsapp.net",
					initiatedByMe: false
				)
			)),
			timestampMilliseconds: 1_700_003_222_000
		)))

		#expect(editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.type == .messageEdit)
		#expect(editedMessage.protocolMessage.editedMessage.protocolMessage.type == .ephemeralSetting)
		#expect(editedMessage.protocolMessage.editedMessage.protocolMessage.ephemeralExpiration == 604_800)
		#expect(editedMessage.protocolMessage.editedMessage.protocolMessage.ephemeralSettingTimestamp == 1_700_003_200)
		#expect(editedMessage.protocolMessage.editedMessage.protocolMessage.disappearingMode.initiator == .bizUpgradeFbHosting)
		#expect(editedMessage.protocolMessage.editedMessage.protocolMessage.disappearingMode.trigger == .bizSupportsFbHosting)
		#expect(editedMessage.protocolMessage.editedMessage.protocolMessage.disappearingMode.initiatorDeviceJid == "258840000000.0@s.whatsapp.net")
		#expect(!editedMessage.protocolMessage.editedMessage.protocolMessage.disappearingMode.initiatedByMe)
	}

	@Test("forwards received edited messages with limit sharing content")
	func forwardsReceivedEditedMessagesWithLimitSharingContent() async throws {
		let editedMessage = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITEDLIMIT",
				participant: nil
			),
			content: .limitSharing(ReceivedLimitSharingContent(
				sharingLimited: true,
				trigger: .bizSupportsFBHosting,
				settingTimestampMilliseconds: 1_717_777_200,
				initiatedByMe: false
			)),
			timestampMilliseconds: 1_700_003_333_000
		)))

		#expect(editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.type == .messageEdit)
		#expect(editedMessage.protocolMessage.editedMessage.protocolMessage.type == .limitSharing)
		#expect(editedMessage.protocolMessage.editedMessage.protocolMessage.limitSharing.sharingLimited)
		#expect(editedMessage.protocolMessage.editedMessage.protocolMessage.limitSharing.trigger == .bizSupportsFbHosting)
		#expect(editedMessage.protocolMessage.editedMessage.protocolMessage.limitSharing.limitSharingSettingTimestamp == 1_717_777_200)
		#expect(!editedMessage.protocolMessage.editedMessage.protocolMessage.limitSharing.initiatedByMe)
	}

	@Test("forwards received edited messages with group member label change content")
	func forwardsReceivedEditedMessagesWithGroupMemberLabelChangeContent() async throws {
		let editedMessage = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITEDMEMBERLABEL",
				participant: nil
			),
			content: .groupMemberLabelChange(ReceivedGroupMemberLabelChangeContent(
				label: "team-a",
				labelTimestamp: 1_700_000_204
			)),
			timestampMilliseconds: 1_700_003_444_000
		)))

		#expect(editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.type == .messageEdit)
		#expect(editedMessage.protocolMessage.editedMessage.protocolMessage.type == .groupMemberLabelChange)
		#expect(editedMessage.protocolMessage.editedMessage.protocolMessage.memberLabel.label == "team-a")
		#expect(editedMessage.protocolMessage.editedMessage.protocolMessage.memberLabel.labelTimestamp == 1_700_000_204)
	}

	@Test("forwards received edited messages with shared phone number content")
	func forwardsReceivedEditedMessagesWithSharedPhoneNumberContent() async throws {
		let editedMessage = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITEDSHAREDPHONE",
				participant: nil
			),
			content: .phoneNumberShared(ReceivedPhoneNumberSharedContent()),
			timestampMilliseconds: 1_700_001_888_000
		)))

		#expect(editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.type == .messageEdit)
		#expect(editedMessage.protocolMessage.editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.editedMessage.protocolMessage.type == .sharePhoneNumber)
	}

	@Test("forwards received edited messages with scheduled call creation content")
	func forwardsReceivedEditedMessagesWithScheduledCallCreationContent() async throws {
		let editedMessage = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITEDSCHEDULEDCALLCREATE",
				participant: nil
			),
			content: .scheduledCallCreation(ReceivedScheduledCallCreationContent(
				scheduledTimestampMilliseconds: 1_700_200_000_000,
				callType: .video,
				title: "Weekly sync"
			)),
			timestampMilliseconds: 1_700_001_999_000
		)))

		#expect(editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.type == .messageEdit)
		#expect(editedMessage.protocolMessage.editedMessage.hasScheduledCallCreationMessage)
		#expect(editedMessage.protocolMessage.editedMessage.scheduledCallCreationMessage.scheduledTimestampMs == 1_700_200_000_000)
		#expect(editedMessage.protocolMessage.editedMessage.scheduledCallCreationMessage.callType == .video)
		#expect(editedMessage.protocolMessage.editedMessage.scheduledCallCreationMessage.title == "Weekly sync")
	}

	@Test("forwards received edited messages with scheduled call edit content")
	func forwardsReceivedEditedMessagesWithScheduledCallEditContent() async throws {
		let editedMessage = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITEDSCHEDULEDCALLCANCEL",
				participant: nil
			),
			content: .scheduledCallEdit(ReceivedScheduledCallEditContent(
				key: ReceivedMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "SCHEDULED_CALL_MESSAGE_ID",
					participant: "258840000000@s.whatsapp.net"
				),
				editType: .cancel
			)),
			timestampMilliseconds: 1_700_002_000_000
		)))

		#expect(editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.type == .messageEdit)
		#expect(editedMessage.protocolMessage.editedMessage.hasScheduledCallEditMessage)
		#expect(editedMessage.protocolMessage.editedMessage.scheduledCallEditMessage.key.id == "SCHEDULED_CALL_MESSAGE_ID")
		#expect(editedMessage.protocolMessage.editedMessage.scheduledCallEditMessage.editType == .cancel)
	}

	@Test("forwards received edited messages with poll creation content")
	func forwardsReceivedEditedMessagesWithPollCreationContent() async throws {
		let editedMessage = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITEDPOLL",
				participant: nil
			),
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
			timestampMilliseconds: 1_700_002_111_000
		)))

		#expect(editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.type == .messageEdit)
		#expect(editedMessage.protocolMessage.editedMessage.hasPollCreationMessageV3)
		#expect(editedMessage.protocolMessage.editedMessage.pollCreationMessageV3.name == "Best Baileys port?")
		#expect(editedMessage.protocolMessage.editedMessage.pollCreationMessageV3.options.map(\.optionName) == ["Swift", "TypeScript"])
		#expect(editedMessage.protocolMessage.editedMessage.pollCreationMessageV3.options.map(\.optionHash) == ["hash-swift", "hash-typescript"])
		#expect(editedMessage.protocolMessage.editedMessage.pollCreationMessageV3.encKey == Data([0x01, 0x02, 0x03]))
		#expect(editedMessage.protocolMessage.editedMessage.pollCreationMessageV3.pollType == .quiz)
		#expect(editedMessage.protocolMessage.editedMessage.pollCreationMessageV3.correctAnswer.optionName == "Swift")
	}

	@Test("forwards received edited messages with poll update content")
	func forwardsReceivedEditedMessagesWithPollUpdateContent() async throws {
		let editedMessage = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITEDPOLLUPDATE",
				participant: nil
			),
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
			timestampMilliseconds: 1_700_002_222_000
		)))

		#expect(editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.type == .messageEdit)
		#expect(editedMessage.protocolMessage.editedMessage.hasPollUpdateMessage)
		#expect(editedMessage.protocolMessage.editedMessage.pollUpdateMessage.pollCreationMessageKey.id == "3EB0POLL")
		#expect(editedMessage.protocolMessage.editedMessage.pollUpdateMessage.vote.encPayload == Data([0x01, 0x02, 0x03]))
		#expect(editedMessage.protocolMessage.editedMessage.pollUpdateMessage.vote.encIv == Data([0x04, 0x05, 0x06]))
		#expect(editedMessage.protocolMessage.editedMessage.pollUpdateMessage.senderTimestampMs == 1_700_002_000_000)
	}

	@Test("forwards received edited messages with poll result snapshot content")
	func forwardsReceivedEditedMessagesWithPollResultSnapshotContent() async throws {
		let editedMessage = try await forwardedMessage(content: .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITEDPOLLRESULT",
				participant: nil
			),
			content: .pollResultSnapshot(ReceivedPollResultSnapshotContent(
				name: "Launch window",
				votes: [ReceivedPollResultVote(optionName: "Morning", voteCount: 7)],
				pollType: .quiz
			)),
			timestampMilliseconds: 1_700_002_333_000
		)))

		#expect(editedMessage.hasProtocolMessage)
		#expect(editedMessage.protocolMessage.type == .messageEdit)
		#expect(editedMessage.protocolMessage.editedMessage.hasPollResultSnapshotMessage)
		#expect(editedMessage.protocolMessage.editedMessage.pollResultSnapshotMessage.name == "Launch window")
		#expect(editedMessage.protocolMessage.editedMessage.pollResultSnapshotMessage.pollVotes.map(\.optionName) == ["Morning"])
		#expect(editedMessage.protocolMessage.editedMessage.pollResultSnapshotMessage.pollVotes.map(\.optionVoteCount) == [7])
		#expect(editedMessage.protocolMessage.editedMessage.pollResultSnapshotMessage.pollType == .quiz)
	}

	private func forwardedMessage(content: ReceivedMessageContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x2f]))],
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
				id: "PROTOCOLACTION1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDPROTOCOLACTION"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
