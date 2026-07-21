import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client community create")
struct WhatsAppClientCommunityCreateTests {
	@Test("creates a community then fetches created group metadata")
	func createsCommunityThenFetchesCreatedGroupMetadata() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageIDGenerator: deterministicMessageIDGenerator()
		)
		try await client.connect()

		let task = Task {
			try await client.communityCreate(
				subject: "Swift Community",
				description: "community body",
				requestID: "community-create-1"
			)
		}
		let createRequest = try await transport.waitForSentNode(at: 0)
		#expect(createRequest.attrs["id"] == "community-create-1")
		#expect(createRequest.attrs["to"] == "@g.us")
		#expect(createRequest.attrs["type"] == "set")
		let create = try #require(createRequest.firstChild(named: "create"))
		#expect(create.attrs["subject"] == "Swift Community")
		let description = try #require(create.firstChild(named: "description"))
		#expect(description.attrs["id"] == "3EB012DFF6F6")
		#expect(description.firstChild(named: "body")?.content == .data(Data("community body".utf8)))
		#expect(create.firstChild(named: "parent")?.attrs["default_membership_approval_mode"] == "request_required")
		#expect(create.firstChild(named: "allow_non_admin_sub_group_creation") != nil)
		#expect(create.firstChild(named: "create_general_chat") != nil)

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-create-1", "type": "result"],
			content: .nodes([BinaryNode(tag: "group", attrs: ["id": "120363000000000010"])])
		))
		let metadataRequest = try await transport.waitForSentNode(at: 1)
		#expect(metadataRequest.attrs["to"] == "120363000000000010@g.us")
		#expect(metadataRequest.attrs["type"] == "get")
		#expect(metadataRequest.firstChild(named: "query")?.attrs["request"] == "interactive")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": metadataRequest.attrs["id"] ?? "", "type": "result"],
			content: .nodes([createdGroupNode(subject: "Swift Community")])
		))
		let metadata = try await task.value
		#expect(metadata.id == "120363000000000010@g.us")
		#expect(metadata.subject == "Swift Community")
		#expect(metadata.isCommunity == true)
	}

	@Test("creates a linked group inside a community")
	func createsLinkedGroupInsideCommunity() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.communityCreateGroup(
				subject: "General",
				participants: ["111@s.whatsapp.net", "222@s.whatsapp.net"],
				parentCommunityJID: "120363000000000010@g.us",
				requestID: "community-create-group-1",
				groupKey: "group-key-1"
			)
		}
		let createRequest = try await transport.waitForSentNode(at: 0)
		#expect(createRequest.attrs["id"] == "community-create-group-1")
		#expect(createRequest.attrs["to"] == "@g.us")
		let create = try #require(createRequest.firstChild(named: "create"))
		#expect(create.attrs["subject"] == "General")
		#expect(create.attrs["key"] == "group-key-1")
		#expect(create.children(named: "participant").map { $0.attrs["jid"] } == [
			"111@s.whatsapp.net",
			"222@s.whatsapp.net"
		])
		#expect(create.firstChild(named: "linked_parent")?.attrs["jid"] == "120363000000000010@g.us")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-create-group-1", "type": "result"],
			content: .nodes([BinaryNode(tag: "group", attrs: ["id": "120363000000000020"])])
		))
		let metadataRequest = try await transport.waitForSentNode(at: 1)
		#expect(metadataRequest.attrs["to"] == "120363000000000020@g.us")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": metadataRequest.attrs["id"] ?? "", "type": "result"],
			content: .nodes([createdGroupNode(id: "120363000000000020", subject: "General")])
		))
		let metadata = try await task.value
		#expect(metadata.id == "120363000000000020@g.us")
		#expect(metadata.subject == "General")
	}
}

private func deterministicMessageIDGenerator() -> MessageIDGenerator {
	MessageIDGenerator(
		unixTimestampSeconds: { 1_700_000_000 },
		randomBytes: { count in
			#expect(count == 16)
			return Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
		}
	)
}

private func createdGroupNode(
	id: String = "120363000000000010",
	subject: String
) -> BinaryNode {
	BinaryNode(
		tag: "group",
		attrs: [
			"id": id,
			"subject": subject,
			"creator": "111@s.whatsapp.net",
			"size": "1"
		],
		content: .nodes([
			BinaryNode(tag: "parent"),
			BinaryNode(tag: "participant", attrs: ["jid": "111@s.whatsapp.net", "type": "superadmin"])
		])
	)
}
