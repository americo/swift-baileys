import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client group notifications")
struct WhatsAppClientGroupNotificationTests {
	@Test("emits subject changes as group stub messages")
	func emitsSubjectChangesAsGroupStubMessages() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: [
				"from": "123@g.us",
				"id": "group-subject-1",
				"participant": "456@s.whatsapp.net",
				"t": "1700000000",
				"type": "w:gp2"
			],
			content: .nodes([
				BinaryNode(tag: "subject", attrs: ["subject": "New subject"])
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "group-subject-1",
			from: "123@g.us",
			timestamp: 1_700_000_000,
			content: .stub(ReceivedMessageStubContent(type: .groupChangeSubject, parameters: ["New subject"])),
			fromMe: false,
			participant: "456@s.whatsapp.net",
			keyParticipant: "456@s.whatsapp.net",
			stub: ReceivedMessageStubContent(type: .groupChangeSubject, parameters: ["New subject"])
		)))
	}

	@Test("emits participant additions as group stub messages and acknowledges them")
	func emitsParticipantAdditionsAsGroupStubMessagesAndAcknowledgesThem() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: [
				"from": "123@g.us",
				"id": "group-add-1",
				"participant": "456@s.whatsapp.net",
				"t": "1700000100",
				"type": "w:gp2"
			],
			content: .nodes([
				BinaryNode(tag: "add", content: .nodes([
					BinaryNode(tag: "participant", attrs: [
						"jid": "789@s.whatsapp.net",
						"type": "admin"
					])
				]))
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "group-add-1",
			from: "123@g.us",
			timestamp: 1_700_000_100,
			content: .stub(ReceivedMessageStubContent(
				type: .groupParticipantAdd,
				parameters: ["{\"id\":\"789@s.whatsapp.net\",\"admin\":\"admin\"}"]
			)),
			fromMe: false,
			participant: "456@s.whatsapp.net",
			keyParticipant: "456@s.whatsapp.net",
			stub: ReceivedMessageStubContent(
				type: .groupParticipantAdd,
				parameters: ["{\"id\":\"789@s.whatsapp.net\",\"admin\":\"admin\"}"]
			)
		)))
		let ack = try await firstGroupNotificationAck(from: transport)
		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: [
				"id": "group-add-1",
				"to": "123@g.us",
				"class": "notification",
				"participant": "456@s.whatsapp.net",
				"type": "w:gp2"
			]
		))
	}

	@Test("emits ephemeral group notifications as ephemeral setting messages")
	func emitsEphemeralGroupNotificationsAsEphemeralSettingMessages() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: [
				"from": "123@g.us",
				"id": "group-ephemeral-1",
				"participant": "456@s.whatsapp.net",
				"t": "1700000200",
				"type": "w:gp2"
			],
			content: .nodes([
				BinaryNode(tag: "ephemeral", attrs: ["expiration": "604800"])
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "group-ephemeral-1",
			from: "123@g.us",
			timestamp: 1_700_000_200,
			content: .ephemeralSetting(ReceivedEphemeralSettingContent(
				expirationSeconds: 604_800,
				settingTimestampSeconds: nil,
				disappearingMode: nil
			)),
			fromMe: false,
			participant: "456@s.whatsapp.net",
			keyParticipant: "456@s.whatsapp.net"
		)))
	}

	@Test("emits group mode notifications as group stub messages")
	func emitsGroupModeNotificationsAsGroupStubMessages() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: [
				"from": "123@g.us",
				"id": "group-mode-1",
				"participant": "456@s.whatsapp.net",
				"t": "1700000300",
				"type": "w:gp2"
			],
			content: .nodes([
				BinaryNode(tag: "member_add_mode", content: .string("admin_add"))
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "group-mode-1",
			from: "123@g.us",
			timestamp: 1_700_000_300,
			content: .stub(ReceivedMessageStubContent(
				type: .groupMemberAddMode,
				parameters: ["admin_add"]
			)),
			fromMe: false,
			participant: "456@s.whatsapp.net",
			keyParticipant: "456@s.whatsapp.net",
			stub: ReceivedMessageStubContent(type: .groupMemberAddMode, parameters: ["admin_add"])
		)))

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: [
				"from": "123@g.us",
				"id": "group-mode-2",
				"participant": "456@s.whatsapp.net",
				"t": "1700000400",
				"type": "w:gp2"
			],
			content: .nodes([
				BinaryNode(tag: "membership_approval_mode", content: .nodes([
					BinaryNode(tag: "group_join", attrs: ["state": "on"])
				]))
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "group-mode-2",
			from: "123@g.us",
			timestamp: 1_700_000_400,
			content: .stub(ReceivedMessageStubContent(
				type: .groupMembershipJoinApprovalMode,
				parameters: ["on"]
			)),
			fromMe: false,
			participant: "456@s.whatsapp.net",
			keyParticipant: "456@s.whatsapp.net",
			stub: ReceivedMessageStubContent(type: .groupMembershipJoinApprovalMode, parameters: ["on"])
		)))
	}

	@Test("emits number change notifications as group stub messages")
	func emitsNumberChangeNotificationsAsGroupStubMessages() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: [
				"from": "123@g.us",
				"id": "group-modify-1",
				"participant": "456@s.whatsapp.net",
				"t": "1700000500",
				"type": "w:gp2"
			],
			content: .nodes([
				BinaryNode(tag: "modify", content: .nodes([
					BinaryNode(tag: "participant", attrs: ["jid": "111@s.whatsapp.net"]),
					BinaryNode(tag: "participant", attrs: ["jid": "222@s.whatsapp.net"])
				]))
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "group-modify-1",
			from: "123@g.us",
			timestamp: 1_700_000_500,
			content: .stub(ReceivedMessageStubContent(
				type: .groupParticipantChangeNumber,
				parameters: ["111@s.whatsapp.net", "222@s.whatsapp.net"]
			)),
			fromMe: false,
			participant: "456@s.whatsapp.net",
			keyParticipant: "456@s.whatsapp.net",
			stub: ReceivedMessageStubContent(
				type: .groupParticipantChangeNumber,
				parameters: ["111@s.whatsapp.net", "222@s.whatsapp.net"]
			)
		)))
	}

	@Test("emits membership request notifications as group stub messages")
	func emitsMembershipRequestNotificationsAsGroupStubMessages() async {
		let client = WhatsAppClient()
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: [
				"from": "123@g.us",
				"id": "group-request-1",
				"participant": "456@s.whatsapp.net",
				"participant_pn": "456@s.whatsapp.net",
				"t": "1700000600",
				"type": "w:gp2"
			],
			content: .nodes([
				BinaryNode(tag: "created_membership_requests", attrs: ["request_method": "invite_link"], content: .nodes([
					BinaryNode(tag: "participant", attrs: [
						"jid": "lid-user@lid",
						"phone_number": "789@s.whatsapp.net"
					])
				]))
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "group-request-1",
			from: "123@g.us",
			timestamp: 1_700_000_600,
			content: .stub(ReceivedMessageStubContent(
				type: .groupMembershipJoinApprovalRequestNonAdminAdd,
				parameters: ["{\"lid\":\"lid-user@lid\",\"pn\":\"789@s.whatsapp.net\"}", "created", "invite_link"]
			)),
			fromMe: false,
			participant: "456@s.whatsapp.net",
			keyParticipant: "456@s.whatsapp.net",
			stub: ReceivedMessageStubContent(
				type: .groupMembershipJoinApprovalRequestNonAdminAdd,
				parameters: ["{\"lid\":\"lid-user@lid\",\"pn\":\"789@s.whatsapp.net\"}", "created", "invite_link"]
			)
		)))

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: [
				"from": "123@g.us",
				"id": "group-request-2",
				"participant": "456@s.whatsapp.net",
				"participant_pn": "456@s.whatsapp.net",
				"t": "1700000700",
				"type": "w:gp2"
			],
			content: .nodes([
				BinaryNode(tag: "revoked_membership_requests", content: .nodes([
					BinaryNode(tag: "participant", attrs: [
						"jid": "456@s.whatsapp.net",
						"phone_number": "456@s.whatsapp.net"
					])
				]))
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "group-request-2",
			from: "123@g.us",
			timestamp: 1_700_000_700,
			content: .stub(ReceivedMessageStubContent(
				type: .groupMembershipJoinApprovalRequestNonAdminAdd,
				parameters: ["{\"lid\":\"456@s.whatsapp.net\",\"pn\":\"456@s.whatsapp.net\"}", "revoked"]
			)),
			fromMe: false,
			participant: "456@s.whatsapp.net",
			keyParticipant: "456@s.whatsapp.net",
			stub: ReceivedMessageStubContent(
				type: .groupMembershipJoinApprovalRequestNonAdminAdd,
				parameters: ["{\"lid\":\"456@s.whatsapp.net\",\"pn\":\"456@s.whatsapp.net\"}", "revoked"]
			)
		)))
	}
}

private func firstGroupNotificationAck(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	let frame = try #require(await transport.sentFrames.first)
	var codec = NoiseFrameCodec()
	return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
}
