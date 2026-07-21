import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client groups")
struct WhatsAppClientGroupTests {
	@Test("queries and parses group metadata")
	func queriesAndParsesGroupMetadata() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageIDGenerator: MessageIDGenerator(
				unixTimestampSeconds: { 1_700_000_000 },
				randomBytes: { Data(repeating: 0x11, count: $0) }
			)
		)
		try await client.connect()

		let task = Task {
			try await client.groupMetadata("120363000000000000@g.us")
		}
		let request = try await transport.waitForSentNode()
		let requestID = try #require(request.attrs["id"])
		#expect(request.tag == "iq")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "w:g2")
		#expect(request.attrs["to"] == "120363000000000000@g.us")
		#expect(request.firstChild(named: "query")?.attrs["request"] == "interactive")

		await transport.enqueueInbound(
			BinaryNode(
				tag: "iq",
				attrs: ["id": requestID, "type": "result"],
				content: .nodes([groupNode()])
			)
		)
		let metadata = try await task.value

		#expect(metadata.id == "120363000000000000@g.us")
		#expect(metadata.subject == "Swift Group")
		#expect(metadata.subjectOwner == "111@s.whatsapp.net")
		#expect(metadata.subjectOwnerPn == "111000@s.whatsapp.net")
		#expect(metadata.subjectOwnerUsername == "subject-owner")
		#expect(metadata.subjectTime == 1_700_000_001)
		#expect(metadata.creation == 1_700_000_000)
		#expect(metadata.owner == "222@s.whatsapp.net")
		#expect(metadata.ownerPn == "222000@s.whatsapp.net")
		#expect(metadata.ownerUsername == "creator-user")
		#expect(metadata.ownerCountryCode == "258")
		#expect(metadata.desc == "group description")
		#expect(metadata.descId == "desc-1")
		#expect(metadata.descOwner == "333@s.whatsapp.net")
		#expect(metadata.descOwnerPn == "333000@s.whatsapp.net")
		#expect(metadata.descOwnerUsername == "desc-owner")
		#expect(metadata.descTime == 1_700_000_002)
		#expect(metadata.restrict == true)
		#expect(metadata.announce == true)
		#expect(metadata.joinApprovalMode == true)
		#expect(metadata.memberAddMode == true)
		#expect(metadata.ephemeralDuration == 86_400)
		#expect(metadata.participants == [
			GroupParticipant(id: "111@s.whatsapp.net", lid: "111@lid", admin: .superadmin),
			GroupParticipant(id: "222@lid", phoneNumber: "222@s.whatsapp.net", username: "member-user", admin: .admin)
		])
	}

	@Test("fetches all participating groups keyed by jid")
	func fetchesAllParticipatingGroupsKeyedByJID() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupFetchAllParticipating(requestID: "groups-all-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.tag == "iq")
		#expect(request.attrs["id"] == "groups-all-1")
		#expect(request.attrs["to"] == "@g.us")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "w:g2")
		let participating = try #require(request.firstChild(named: "participating"))
		#expect(participating.firstChild(named: "participants") != nil)
		#expect(participating.firstChild(named: "description") != nil)

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "groups-all-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "groups", content: .nodes([
					groupNode(id: "120363000000000000", subject: "Swift Group"),
					groupNode(id: "120363000000000001", subject: "Second Group")
				]))
			])
		))
		let groups = try await task.value
		#expect(groups.keys.sorted() == [
			"120363000000000000@g.us",
			"120363000000000001@g.us"
		])
		#expect(groups["120363000000000000@g.us"]?.subject == "Swift Group")
		#expect(groups["120363000000000001@g.us"]?.subject == "Second Group")
	}

	@Test("creates groups with participant nodes and parses metadata")
	func createsGroupsWithParticipantNodesAndParsesMetadata() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupCreate(
				subject: "Swift Group",
				participants: ["111@s.whatsapp.net", "222@s.whatsapp.net"],
				requestID: "create-1",
				groupKey: "group-key-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "create-1")
		#expect(request.attrs["to"] == "@g.us")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "w:g2")
		let create = try #require(request.firstChild(named: "create"))
		#expect(create.attrs["subject"] == "Swift Group")
		#expect(create.attrs["key"] == "group-key-1")
		#expect(create.children(named: "participant").map { $0.attrs["jid"] } == [
			"111@s.whatsapp.net",
			"222@s.whatsapp.net"
		])

		await transport.enqueueInbound(
			BinaryNode(
				tag: "iq",
				attrs: ["id": "create-1", "type": "result"],
				content: .nodes([groupNode()])
			)
		)
		let metadata = try await task.value

		#expect(metadata.id == "120363000000000000@g.us")
		#expect(metadata.subject == "Swift Group")
	}

	@Test("leaves groups by sending a leave node")
	func leavesGroupsBySendingLeaveNode() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupLeave("120363000000000000@g.us", requestID: "leave-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "leave-1")
		#expect(request.attrs["to"] == "@g.us")
		#expect(request.attrs["type"] == "set")
		let leave = try #require(request.firstChild(named: "leave"))
		#expect(leave.firstChild(named: "group")?.attrs["id"] == "120363000000000000@g.us")

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "leave-1", "type": "result"]))
		try await task.value
	}

	@Test("updates group participants and parses per participant status")
	func updatesGroupParticipantsAndParsesStatus() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupParticipantsUpdate(
				"120363000000000000@g.us",
				participants: ["111@s.whatsapp.net", "222@s.whatsapp.net"],
				action: .add,
				requestID: "participants-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "participants-1")
		#expect(request.attrs["to"] == "120363000000000000@g.us")
		let add = try #require(request.firstChild(named: "add"))
		#expect(add.children(named: "participant").map { $0.attrs["jid"] } == [
			"111@s.whatsapp.net",
			"222@s.whatsapp.net"
		])

		await transport.enqueueInbound(
			BinaryNode(
				tag: "iq",
				attrs: ["id": "participants-1", "type": "result"],
				content: .nodes([
					BinaryNode(tag: "add", content: .nodes([
						BinaryNode(tag: "participant", attrs: ["jid": "111@s.whatsapp.net"]),
						BinaryNode(tag: "participant", attrs: ["jid": "222@s.whatsapp.net", "error": "403"])
					]))
				])
			)
		)
		let results = try await task.value

		#expect(results.map(\.jid) == ["111@s.whatsapp.net", "222@s.whatsapp.net"])
		#expect(results.map(\.status) == ["200", "403"])
		#expect(results.first?.content?.attrs["jid"] == "111@s.whatsapp.net")
		#expect(results.last?.content?.attrs["error"] == "403")
	}

	@Test("updates group subject with UTF-8 content")
	func updatesGroupSubjectWithUTF8Content() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupUpdateSubject(
				"120363000000000000@g.us",
				subject: "Novo Grupo Swift",
				requestID: "subject-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "subject-1")
		#expect(request.attrs["to"] == "120363000000000000@g.us")
		let subject = try #require(request.firstChild(named: "subject"))
		#expect(subject.content == .data(Data("Novo Grupo Swift".utf8)))

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "subject-1", "type": "result"]))
		try await task.value
	}

	@Test("updates group description with previous description id")
	func updatesGroupDescriptionWithPreviousDescriptionID() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupUpdateDescription(
				"120363000000000000@g.us",
				description: "Nova descrição Swift",
				requestID: "description-set-1"
			)
		}
		let metadataRequest = try await transport.waitForSentNode(at: 0)
		let metadataRequestID = try #require(metadataRequest.attrs["id"])
		#expect(metadataRequest.attrs["type"] == "get")
		#expect(metadataRequest.firstChild(named: "query")?.attrs["request"] == "interactive")
		await transport.enqueueInbound(
			BinaryNode(
				tag: "iq",
				attrs: ["id": metadataRequestID, "type": "result"],
				content: .nodes([groupNode()])
			)
		)

		let updateRequest = try await transport.waitForSentNode(at: 1)
		#expect(updateRequest.attrs["id"] == "description-set-1")
		#expect(updateRequest.attrs["type"] == "set")
		let description = try #require(updateRequest.firstChild(named: "description"))
		#expect(description.attrs["prev"] == "desc-1")
		#expect(description.attrs["id"] != nil)
		#expect(description.attrs["delete"] == nil)
		let body = try #require(description.firstChild(named: "body"))
		#expect(body.content == .data(Data("Nova descrição Swift".utf8)))

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "description-set-1", "type": "result"]))
		try await task.value
	}

	@Test("deletes group description with previous description id")
	func deletesGroupDescriptionWithPreviousDescriptionID() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupUpdateDescription(
				"120363000000000000@g.us",
				description: nil,
				requestID: "description-delete-1"
			)
		}
		let metadataRequest = try await transport.waitForSentNode(at: 0)
		let metadataRequestID = try #require(metadataRequest.attrs["id"])
		await transport.enqueueInbound(
			BinaryNode(
				tag: "iq",
				attrs: ["id": metadataRequestID, "type": "result"],
				content: .nodes([groupNode()])
			)
		)

		let updateRequest = try await transport.waitForSentNode(at: 1)
		#expect(updateRequest.attrs["id"] == "description-delete-1")
		let description = try #require(updateRequest.firstChild(named: "description"))
		#expect(description.attrs["delete"] == "true")
		#expect(description.attrs["prev"] == "desc-1")
		#expect(description.firstChild(named: "body") == nil)

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "description-delete-1", "type": "result"]))
		try await task.value
	}

	@Test("toggles group ephemeral settings")
	func togglesGroupEphemeralSettings() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let enableTask = Task {
			try await client.groupToggleEphemeral(
				"120363000000000000@g.us",
				expirationSeconds: 86_400,
				requestID: "ephemeral-enable-1"
			)
		}
		let enableRequest = try await transport.waitForSentNode(at: 0)
		#expect(enableRequest.attrs["id"] == "ephemeral-enable-1")
		#expect(enableRequest.attrs["type"] == "set")
		#expect(enableRequest.firstChild(named: "ephemeral")?.attrs["expiration"] == "86400")
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "ephemeral-enable-1", "type": "result"]))
		try await enableTask.value

		let disableTask = Task {
			try await client.groupToggleEphemeral(
				"120363000000000000@g.us",
				expirationSeconds: 0,
				requestID: "ephemeral-disable-1"
			)
		}
		let disableRequest = try await transport.waitForSentNode(at: 1)
		#expect(disableRequest.attrs["id"] == "ephemeral-disable-1")
		#expect(disableRequest.firstChild(named: "not_ephemeral") != nil)
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "ephemeral-disable-1", "type": "result"]))
		try await disableTask.value
	}

	@Test("updates group admin settings")
	func updatesGroupAdminSettings() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupSettingUpdate(
				"120363000000000000@g.us",
				setting: .announcement,
				requestID: "setting-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "setting-1")
		#expect(request.attrs["type"] == "set")
		#expect(request.firstChild(named: "announcement") != nil)

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "setting-1", "type": "result"]))
		try await task.value
	}

	@Test("updates group member add and join approval modes")
	func updatesGroupMemberAddAndJoinApprovalModes() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let memberAddTask = Task {
			try await client.groupMemberAddMode(
				"120363000000000000@g.us",
				mode: .allMemberAdd,
				requestID: "member-add-mode-1"
			)
		}
		let memberAddRequest = try await transport.waitForSentNode(at: 0)
		let memberAddMode = try #require(memberAddRequest.firstChild(named: "member_add_mode"))
		#expect(memberAddRequest.attrs["id"] == "member-add-mode-1")
		#expect(memberAddMode.content == .data(Data("all_member_add".utf8)))
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "member-add-mode-1", "type": "result"]))
		try await memberAddTask.value

		let approvalTask = Task {
			try await client.groupJoinApprovalMode(
				"120363000000000000@g.us",
				mode: .on,
				requestID: "join-approval-1"
			)
		}
		let approvalRequest = try await transport.waitForSentNode(at: 1)
		let approvalMode = try #require(approvalRequest.firstChild(named: "membership_approval_mode"))
		#expect(approvalRequest.attrs["id"] == "join-approval-1")
		#expect(approvalMode.firstChild(named: "group_join")?.attrs["state"] == "on")
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "join-approval-1", "type": "result"]))
		try await approvalTask.value
	}

	@Test("gets and revokes group invite codes")
	func getsAndRevokesGroupInviteCodes() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let getTask = Task {
			try await client.groupInviteCode("120363000000000000@g.us", requestID: "invite-get-1")
		}
		let getRequest = try await transport.waitForSentNode(at: 0)
		#expect(getRequest.attrs["type"] == "get")
		#expect(getRequest.firstChild(named: "invite") != nil)
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "invite-get-1", "type": "result"],
			content: .nodes([BinaryNode(tag: "invite", attrs: ["code": "ABC123"])])
		))
		#expect(try await getTask.value == "ABC123")

		let revokeTask = Task {
			try await client.groupRevokeInvite("120363000000000000@g.us", requestID: "invite-revoke-1")
		}
		let revokeRequest = try await transport.waitForSentNode(at: 1)
		#expect(revokeRequest.attrs["type"] == "set")
		#expect(revokeRequest.firstChild(named: "invite") != nil)
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "invite-revoke-1", "type": "result"],
			content: .nodes([BinaryNode(tag: "invite", attrs: ["code": "XYZ789"])])
		))
		#expect(try await revokeTask.value == "XYZ789")
	}

	@Test("accepts group invites and returns the joined group jid")
	func acceptsGroupInvitesAndReturnsJoinedGroupJID() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupAcceptInvite(code: "ABC123", requestID: "accept-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "accept-1")
		#expect(request.attrs["to"] == "@g.us")
		#expect(request.attrs["type"] == "set")
		#expect(request.firstChild(named: "invite")?.attrs["code"] == "ABC123")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "accept-1", "type": "result"],
			content: .nodes([BinaryNode(tag: "group", attrs: ["jid": "120363000000000000@g.us"])])
		))
		#expect(try await task.value == "120363000000000000@g.us")
	}
}

actor MockGroupWebSocketTransport: WhatsAppWebSocketTransport {
	private var sentFrames: [Data] = []
	private var inboundContinuations: [CheckedContinuation<Data?, Error>] = []
	private var inboundFrames: [Data?] = []

	func connect() async throws {}

	func send(_ data: Data) async throws {
		sentFrames.append(data)
	}

	func receive() async throws -> Data? {
		try await withCheckedThrowingContinuation { continuation in
			if !inboundFrames.isEmpty {
				continuation.resume(returning: inboundFrames.removeFirst())
			} else {
				inboundContinuations.append(continuation)
			}
		}
	}

	func close() async {
		resumeInbound(nil)
	}

	func waitForSentNode(at index: Int = 0) async throws -> BinaryNode {
		while sentFrames.count <= index {
			try await Task.sleep(for: .milliseconds(1))
		}

		var codec = NoiseFrameCodec()
		return try BinaryNodeDecoder().decode(codec.decode(sentFrames[index])[0])
	}

	func enqueueInbound(_ node: BinaryNode) {
		let data = try! BinaryNodeEncoder().encode(node)
		var codec = NoiseFrameCodec()
		resumeInbound(codec.encode(data))
	}

	private func resumeInbound(_ data: Data?) {
		if inboundContinuations.isEmpty {
			inboundFrames.append(data)
		} else {
			inboundContinuations.removeFirst().resume(returning: data)
		}
	}
}

func groupNode(
	id: String = "120363000000000000",
	subject: String = "Swift Group"
) -> BinaryNode {
	BinaryNode(
		tag: "group",
		attrs: [
			"id": id,
			"subject": subject,
			"s_o": "111@s.whatsapp.net",
			"s_o_pn": "111000@s.whatsapp.net",
			"s_o_username": "subject-owner",
			"s_t": "1700000001",
			"creation": "1700000000",
			"creator": "222@s.whatsapp.net",
			"creator_pn": "222000@s.whatsapp.net",
			"creator_username": "creator-user",
			"creator_country_code": "258",
			"size": "2"
		],
		content: .nodes([
			BinaryNode(
				tag: "description",
				attrs: [
					"id": "desc-1",
					"participant": "333@s.whatsapp.net",
					"participant_pn": "333000@s.whatsapp.net",
					"participant_username": "desc-owner",
					"t": "1700000002"
				],
				content: .nodes([
					BinaryNode(tag: "body", content: .string("group description"))
				])
			),
			BinaryNode(tag: "locked"),
			BinaryNode(tag: "announcement"),
			BinaryNode(tag: "membership_approval_mode"),
			BinaryNode(tag: "member_add_mode", content: .string("all_member_add")),
			BinaryNode(tag: "ephemeral", attrs: ["expiration": "86400"]),
			BinaryNode(tag: "participant", attrs: ["jid": "111@s.whatsapp.net", "lid": "111@lid", "type": "superadmin"]),
			BinaryNode(
				tag: "participant",
				attrs: [
					"jid": "222@lid",
					"phone_number": "222@s.whatsapp.net",
					"participant_username": "member-user",
					"type": "admin"
				]
			)
		])
	)
}
