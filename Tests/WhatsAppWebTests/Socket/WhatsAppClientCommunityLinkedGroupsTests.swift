import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client community linked groups")
struct WhatsAppClientCommunityLinkedGroupsTests {
	@Test("fetches linked groups for a community jid")
	func fetchesLinkedGroupsForCommunityJID() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.communityFetchLinkedGroups(
				"120363000000000010@g.us",
				requestID: "linked-groups-1"
			)
		}
		let metadataRequest = try await transport.waitForSentNode(at: 0)
		#expect(metadataRequest.attrs["to"] == "120363000000000010@g.us")
		#expect(metadataRequest.attrs["type"] == "get")
		#expect(metadataRequest.firstChild(named: "query")?.attrs["request"] == "interactive")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": metadataRequest.attrs["id"] ?? "", "type": "result"],
			content: .nodes([groupNode(isCommunity: true)])
		))
		let linkedRequest = try await transport.waitForSentNode(at: 1)
		#expect(linkedRequest.attrs["id"] == "linked-groups-1")
		#expect(linkedRequest.attrs["to"] == "120363000000000010@g.us")
		#expect(linkedRequest.attrs["type"] == "get")
		#expect(linkedRequest.firstChild(named: "sub_groups") != nil)

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "linked-groups-1", "type": "result"],
			content: .nodes([subGroupsNode()])
		))
		let result = try await task.value
		#expect(result.communityJID == "120363000000000010@g.us")
		#expect(result.isCommunity == true)
		#expect(result.linkedGroups == [
			CommunityLinkedGroup(
				id: "120363000000000020@g.us",
				subject: "Announcements",
				creation: 1_700_000_300,
				owner: "111@s.whatsapp.net",
				size: 12
			),
			CommunityLinkedGroup(
				id: "120363000000000021@g.us",
				subject: "General",
				creation: nil,
				owner: nil,
				size: nil
			)
		])
	}

	@Test("fetches linked groups from linked parent when input is a subgroup")
	func fetchesLinkedGroupsFromLinkedParentWhenInputIsSubgroup() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.communityFetchLinkedGroups(
				"120363000000000020@g.us",
				requestID: "linked-groups-2"
			)
		}
		let metadataRequest = try await transport.waitForSentNode(at: 0)
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": metadataRequest.attrs["id"] ?? "", "type": "result"],
			content: .nodes([groupNode(linkedParent: "120363000000000010@g.us")])
		))
		let linkedRequest = try await transport.waitForSentNode(at: 1)
		#expect(linkedRequest.attrs["id"] == "linked-groups-2")
		#expect(linkedRequest.attrs["to"] == "120363000000000010@g.us")
		#expect(linkedRequest.firstChild(named: "sub_groups") != nil)

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "linked-groups-2", "type": "result"],
			content: .nodes([subGroupsNode()])
		))
		let result = try await task.value
		#expect(result.communityJID == "120363000000000010@g.us")
		#expect(result.isCommunity == false)
		#expect(result.linkedGroups.first?.id == "120363000000000020@g.us")
	}
}

private func groupNode(isCommunity: Bool = false, linkedParent: String? = nil) -> BinaryNode {
	var children: [BinaryNode] = []
	if isCommunity {
		children.append(BinaryNode(tag: "parent"))
	}

	if let linkedParent {
		children.append(BinaryNode(tag: "linked_parent", attrs: ["jid": linkedParent]))
	}

	return BinaryNode(
		tag: "group",
		attrs: [
			"id": "120363000000000010",
			"subject": "Swift Community",
			"creator": "111@s.whatsapp.net",
			"size": "1"
		],
		content: .nodes(children)
	)
}

private func subGroupsNode() -> BinaryNode {
	BinaryNode(tag: "sub_groups", content: .nodes([
		BinaryNode(
			tag: "group",
			attrs: [
				"id": "120363000000000020",
				"subject": "Announcements",
				"creation": "1700000300",
				"creator": "111@s.whatsapp.net",
				"size": "12"
			]
		),
		BinaryNode(
			tag: "group",
			attrs: [
				"id": "120363000000000021",
				"subject": "General"
			]
		)
	]))
}
