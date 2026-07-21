import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client communities")
struct WhatsAppClientCommunityTests {
	@Test("queries and parses community metadata")
	func queriesAndParsesCommunityMetadata() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.communityMetadata("120363000000000010@g.us", requestID: "community-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "community-1")
		#expect(request.attrs["to"] == "120363000000000010@g.us")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "w:g2")
		#expect(request.firstChild(named: "query")?.attrs["request"] == "interactive")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-1", "type": "result"],
			content: .nodes([communityNode()])
		))
		let metadata = try await task.value
		#expect(metadata.id == "120363000000000010@g.us")
		#expect(metadata.subject == "Swift Community")
		#expect(metadata.isCommunity == true)
		#expect(metadata.isCommunityAnnounce == true)
		#expect(metadata.joinApprovalMode == true)
		#expect(metadata.memberAddMode == true)
		#expect(metadata.desc == "community description")
		#expect(metadata.participants == [
			GroupParticipant(id: "111@s.whatsapp.net", admin: .superadmin)
		])
	}

	@Test("fetches all participating communities keyed by jid")
	func fetchesAllParticipatingCommunitiesKeyedByJID() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.communityFetchAllParticipating(requestID: "communities-all-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "communities-all-1")
		#expect(request.attrs["to"] == "@g.us")
		#expect(request.attrs["type"] == "get")
		let participating = try #require(request.firstChild(named: "participating"))
		#expect(participating.firstChild(named: "participants") != nil)
		#expect(participating.firstChild(named: "description") != nil)

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "communities-all-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "communities", content: .nodes([
					communityNode(id: "120363000000000010", subject: "Swift Community"),
					communityNode(id: "120363000000000011", subject: "Second Community")
				]))
			])
		))
		let communities = try await task.value
		#expect(communities.keys.sorted() == [
			"120363000000000010@g.us",
			"120363000000000011@g.us"
		])
		#expect(communities["120363000000000010@g.us"]?.subject == "Swift Community")
		#expect(communities["120363000000000011@g.us"]?.subject == "Second Community")
	}

	@Test("leaves communities by sending a community leave node")
	func leavesCommunitiesBySendingCommunityLeaveNode() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.communityLeave("120363000000000010@g.us", requestID: "community-leave-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "community-leave-1")
		#expect(request.attrs["to"] == "@g.us")
		#expect(request.attrs["type"] == "set")
		let leave = try #require(request.firstChild(named: "leave"))
		#expect(leave.firstChild(named: "community")?.attrs["id"] == "120363000000000010@g.us")

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "community-leave-1", "type": "result"]))
		try await task.value
	}

	@Test("updates community subject with UTF-8 content")
	func updatesCommunitySubjectWithUTF8Content() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.communityUpdateSubject(
				"120363000000000010@g.us",
				subject: "Nova Comunidade Swift",
				requestID: "community-subject-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "community-subject-1")
		#expect(request.attrs["to"] == "120363000000000010@g.us")
		let subject = try #require(request.firstChild(named: "subject"))
		#expect(subject.content == .data(Data("Nova Comunidade Swift".utf8)))

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "community-subject-1", "type": "result"]))
		try await task.value
	}

	@Test("links and unlinks groups from communities")
	func linksAndUnlinksGroupsFromCommunities() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let linkTask = Task {
			try await client.communityLinkGroup(
				groupJID: "120363000000000020@g.us",
				parentCommunityJID: "120363000000000010@g.us",
				requestID: "community-link-1"
			)
		}
		let linkRequest = try await transport.waitForSentNode(at: 0)
		#expect(linkRequest.attrs["id"] == "community-link-1")
		#expect(linkRequest.attrs["to"] == "120363000000000010@g.us")
		let link = try #require(linkRequest.firstChild(named: "links")?.firstChild(named: "link"))
		#expect(link.attrs["link_type"] == "sub_group")
		#expect(link.firstChild(named: "group")?.attrs["jid"] == "120363000000000020@g.us")
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "community-link-1", "type": "result"]))
		try await linkTask.value

		let unlinkTask = Task {
			try await client.communityUnlinkGroup(
				groupJID: "120363000000000020@g.us",
				parentCommunityJID: "120363000000000010@g.us",
				requestID: "community-unlink-1"
			)
		}
		let unlinkRequest = try await transport.waitForSentNode(at: 1)
		#expect(unlinkRequest.attrs["id"] == "community-unlink-1")
		let unlink = try #require(unlinkRequest.firstChild(named: "unlink"))
		#expect(unlink.attrs["unlink_type"] == "sub_group")
		#expect(unlink.firstChild(named: "group")?.attrs["jid"] == "120363000000000020@g.us")
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "community-unlink-1", "type": "result"]))
		try await unlinkTask.value
	}

	@Test("updates community participants with linked groups removal flag")
	func updatesCommunityParticipantsWithLinkedGroupsRemovalFlag() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.communityParticipantsUpdate(
				"120363000000000010@g.us",
				participants: ["111@s.whatsapp.net", "222@s.whatsapp.net"],
				action: .remove,
				requestID: "community-participants-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "community-participants-1")
		let remove = try #require(request.firstChild(named: "remove"))
		#expect(remove.attrs["linked_groups"] == "true")
		#expect(remove.children(named: "participant").map { $0.attrs["jid"] } == [
			"111@s.whatsapp.net",
			"222@s.whatsapp.net"
		])

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-participants-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "remove", content: .nodes([
					BinaryNode(tag: "participant", attrs: ["jid": "111@s.whatsapp.net"]),
					BinaryNode(tag: "participant", attrs: ["jid": "222@s.whatsapp.net", "error": "403"])
				]))
			])
		))
		let results = try await task.value
		#expect(results.map(\.jid) == ["111@s.whatsapp.net", "222@s.whatsapp.net"])
		#expect(results.map(\.status) == ["200", "403"])
		#expect(results.first?.content?.attrs["jid"] == "111@s.whatsapp.net")
		#expect(results.last?.content?.attrs["error"] == "403")
	}

	@Test("gets revokes and accepts community invites")
	func getsRevokesAndAcceptsCommunityInvites() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let getTask = Task {
			try await client.communityInviteCode("120363000000000010@g.us", requestID: "community-invite-get-1")
		}
		let getRequest = try await transport.waitForSentNode(at: 0)
		#expect(getRequest.attrs["type"] == "get")
		#expect(getRequest.firstChild(named: "invite") != nil)
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-invite-get-1", "type": "result"],
			content: .nodes([BinaryNode(tag: "invite", attrs: ["code": "COM123"])])
		))
		#expect(try await getTask.value == "COM123")

		let revokeTask = Task {
			try await client.communityRevokeInvite("120363000000000010@g.us", requestID: "community-invite-revoke-1")
		}
		let revokeRequest = try await transport.waitForSentNode(at: 1)
		#expect(revokeRequest.attrs["type"] == "set")
		#expect(revokeRequest.firstChild(named: "invite") != nil)
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-invite-revoke-1", "type": "result"],
			content: .nodes([BinaryNode(tag: "invite", attrs: ["code": "COM456"])])
		))
		#expect(try await revokeTask.value == "COM456")

		let acceptTask = Task {
			try await client.communityAcceptInvite(code: "COM456", requestID: "community-accept-1")
		}
		let acceptRequest = try await transport.waitForSentNode(at: 2)
		#expect(acceptRequest.attrs["to"] == "@g.us")
		#expect(acceptRequest.attrs["type"] == "set")
		#expect(acceptRequest.firstChild(named: "invite")?.attrs["code"] == "COM456")
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-accept-1", "type": "result"],
			content: .nodes([BinaryNode(tag: "community", attrs: ["jid": "120363000000000010@g.us"])])
		))
		#expect(try await acceptTask.value == "120363000000000010@g.us")
	}

	@Test("updates community settings and modes")
	func updatesCommunitySettingsAndModes() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let settingTask = Task {
			try await client.communitySettingUpdate(
				"120363000000000010@g.us",
				setting: .announcement,
				requestID: "community-setting-1"
			)
		}
		let settingRequest = try await transport.waitForSentNode(at: 0)
		#expect(settingRequest.firstChild(named: "announcement") != nil)
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "community-setting-1", "type": "result"]))
		try await settingTask.value

		let memberTask = Task {
			try await client.communityMemberAddMode(
				"120363000000000010@g.us",
				mode: .allMemberAdd,
				requestID: "community-member-add-1"
			)
		}
		let memberRequest = try await transport.waitForSentNode(at: 1)
		#expect(memberRequest.firstChild(named: "member_add_mode")?.content == .data(Data("all_member_add".utf8)))
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "community-member-add-1", "type": "result"]))
		try await memberTask.value

		let approvalTask = Task {
			try await client.communityJoinApprovalMode(
				"120363000000000010@g.us",
				mode: .on,
				requestID: "community-approval-1"
			)
		}
		let approvalRequest = try await transport.waitForSentNode(at: 2)
		let approvalMode = try #require(approvalRequest.firstChild(named: "membership_approval_mode"))
		#expect(approvalMode.firstChild(named: "community_join")?.attrs["state"] == "on")
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "community-approval-1", "type": "result"]))
		try await approvalTask.value
	}

	@Test("updates and deletes community descriptions with previous description id")
	func updatesAndDeletesCommunityDescriptionsWithPreviousDescriptionID() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let updateTask = Task {
			try await client.communityUpdateDescription(
				"120363000000000010@g.us",
				description: "Nova descrição da comunidade",
				requestID: "community-description-set-1"
			)
		}
		let metadataRequest = try await transport.waitForSentNode(at: 0)
		let metadataRequestID = try #require(metadataRequest.attrs["id"])
		#expect(metadataRequest.attrs["type"] == "get")
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": metadataRequestID, "type": "result"],
			content: .nodes([communityNode()])
		))
		let updateRequest = try await transport.waitForSentNode(at: 1)
		let description = try #require(updateRequest.firstChild(named: "description"))
		#expect(updateRequest.attrs["id"] == "community-description-set-1")
		#expect(description.attrs["prev"] == "community-desc-1")
		#expect(description.attrs["id"] != nil)
		#expect(description.firstChild(named: "body")?.content == .data(Data("Nova descrição da comunidade".utf8)))
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-description-set-1", "type": "result"]
		))
		try await updateTask.value

		let deleteTask = Task {
			try await client.communityUpdateDescription(
				"120363000000000010@g.us",
				description: nil,
				requestID: "community-description-delete-1"
			)
		}
		let deleteMetadataRequest = try await transport.waitForSentNode(at: 2)
		let deleteMetadataRequestID = try #require(deleteMetadataRequest.attrs["id"])
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": deleteMetadataRequestID, "type": "result"],
			content: .nodes([communityNode()])
		))
		let deleteRequest = try await transport.waitForSentNode(at: 3)
		let deleteDescription = try #require(deleteRequest.firstChild(named: "description"))
		#expect(deleteRequest.attrs["id"] == "community-description-delete-1")
		#expect(deleteDescription.attrs["delete"] == "true")
		#expect(deleteDescription.attrs["prev"] == "community-desc-1")
		#expect(deleteDescription.firstChild(named: "body") == nil)
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-description-delete-1", "type": "result"]
		))
		try await deleteTask.value
	}

	@Test("gets community invite info revokes v4 invites and toggles ephemeral")
	func getsCommunityInviteInfoRevokesV4InvitesAndTogglesEphemeral() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let infoTask = Task {
			try await client.communityGetInviteInfo(code: "COMINFO", requestID: "community-info-1")
		}
		let infoRequest = try await transport.waitForSentNode(at: 0)
		#expect(infoRequest.attrs["to"] == "@g.us")
		#expect(infoRequest.attrs["type"] == "get")
		#expect(infoRequest.firstChild(named: "invite")?.attrs["code"] == "COMINFO")
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-info-1", "type": "result"],
			content: .nodes([communityNode()])
		))
		#expect(try await infoTask.value.subject == "Swift Community")

		let revokeTask = Task {
			try await client.communityRevokeInviteV4(
				communityJID: "120363000000000010@g.us",
				invitedJID: "333@s.whatsapp.net",
				requestID: "community-revoke-v4-1"
			)
		}
		let revokeRequest = try await transport.waitForSentNode(at: 1)
		#expect(revokeRequest.attrs["to"] == "120363000000000010@g.us")
		let revoke = try #require(revokeRequest.firstChild(named: "revoke"))
		#expect(revoke.firstChild(named: "participant")?.attrs["jid"] == "333@s.whatsapp.net")
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "community-revoke-v4-1", "type": "result"]))
		#expect(try await revokeTask.value == true)

		let enableTask = Task {
			try await client.communityToggleEphemeral(
				"120363000000000010@g.us",
				expirationSeconds: 86_400,
				requestID: "community-ephemeral-enable-1"
			)
		}
		let enableRequest = try await transport.waitForSentNode(at: 2)
		#expect(enableRequest.firstChild(named: "ephemeral")?.attrs["expiration"] == "86400")
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-ephemeral-enable-1", "type": "result"]
		))
		try await enableTask.value

		let disableTask = Task {
			try await client.communityToggleEphemeral(
				"120363000000000010@g.us",
				expirationSeconds: 0,
				requestID: "community-ephemeral-disable-1"
			)
		}
		let disableRequest = try await transport.waitForSentNode(at: 3)
		#expect(disableRequest.firstChild(named: "not_ephemeral") != nil)
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-ephemeral-disable-1", "type": "result"]
		))
		try await disableTask.value
	}
}

func communityNode(
	id: String = "120363000000000010",
	subject: String = "Swift Community"
) -> BinaryNode {
	BinaryNode(
		tag: "community",
		attrs: [
			"id": id,
			"subject": subject,
			"s_o": "111@s.whatsapp.net",
			"s_t": "1700000201",
			"creation": "1700000200",
			"creator": "111@s.whatsapp.net"
		],
		content: .nodes([
			BinaryNode(
				tag: "description",
				attrs: ["id": "community-desc-1", "participant": "111@s.whatsapp.net", "t": "1700000202"],
				content: .nodes([
					BinaryNode(tag: "body", content: .string("community description"))
				])
			),
			BinaryNode(tag: "parent"),
			BinaryNode(tag: "default_sub_community"),
			BinaryNode(tag: "membership_approval_mode"),
			BinaryNode(tag: "member_add_mode", content: .string("all_member_add")),
			BinaryNode(tag: "participant", attrs: ["jid": "111@s.whatsapp.net", "type": "superadmin"])
		])
	)
}
