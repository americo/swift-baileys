import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client community aliases")
struct WhatsAppClientCommunityAliasTests {
	@Test("Baileys community create alias sends create stanza")
	func baileysCommunityCreateAliasSendsCreateStanza() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.communityCreate("Swift Community", "Description", requestID: "community-create-alias")
		}
		let createRequest = try await transport.waitForSentNode(at: 0)
		let create = try #require(createRequest.firstChild(named: "create"))
		#expect(createRequest.attrs["id"] == "community-create-alias")
		#expect(create.attrs["subject"] == "Swift Community")
		#expect(create.firstChild(named: "description")?.firstChild(named: "body")?.content == .data(Data("Description".utf8)))

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-create-alias", "type": "result"],
			content: .nodes([BinaryNode(tag: "group", attrs: ["id": "120363000000000010"])])
		))
		let metadataRequest = try await transport.waitForSentNode(at: 1)
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": metadataRequest.attrs["id"] ?? "", "type": "result"],
			content: .nodes([groupNode(id: "120363000000000010", subject: "Swift Community")])
		))
		#expect(try await task.value.id == "120363000000000010@g.us")
	}

	@Test("Baileys community create group alias sends linked parent")
	func baileysCommunityCreateGroupAliasSendsLinkedParent() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.communityCreateGroup(
				"Subgroup",
				["111@s.whatsapp.net"],
				"120363000000000010@g.us",
				requestID: "community-create-group-alias",
				groupKey: "subgroup-key"
			)
		}
		let createRequest = try await transport.waitForSentNode(at: 0)
		let create = try #require(createRequest.firstChild(named: "create"))
		#expect(create.attrs["subject"] == "Subgroup")
		#expect(create.attrs["key"] == "subgroup-key")
		#expect(create.firstChild(named: "linked_parent")?.attrs["jid"] == "120363000000000010@g.us")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-create-group-alias", "type": "result"],
			content: .nodes([BinaryNode(tag: "group", attrs: ["id": "120363000000000020"])])
		))
		let metadataRequest = try await transport.waitForSentNode(at: 1)
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": metadataRequest.attrs["id"] ?? "", "type": "result"],
			content: .nodes([groupNode(id: "120363000000000020", subject: "Subgroup")])
		))
		#expect(try await task.value.subject == "Subgroup")
	}

	@Test("Baileys community link aliases send link and unlink stanzas")
	func baileysCommunityLinkAliasesSendLinkAndUnlinkStanzas() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let linkTask = Task {
			try await client.communityLinkGroup(
				"120363000000000020@g.us",
				"120363000000000010@g.us",
				requestID: "community-link-alias"
			)
		}
		let linkRequest = try await transport.waitForSentNode(at: 0)
		let link = try #require(linkRequest.firstChild(named: "links")?.firstChild(named: "link"))
		#expect(link.attrs["link_type"] == "sub_group")
		#expect(link.firstChild(named: "group")?.attrs["jid"] == "120363000000000020@g.us")
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "community-link-alias", "type": "result"]))
		try await linkTask.value

		let unlinkTask = Task {
			try await client.communityUnlinkGroup(
				"120363000000000020@g.us",
				"120363000000000010@g.us",
				requestID: "community-unlink-alias"
			)
		}
		let unlinkRequest = try await transport.waitForSentNode(at: 1)
		let unlink = try #require(unlinkRequest.firstChild(named: "unlink"))
		#expect(unlink.attrs["unlink_type"] == "sub_group")
		#expect(unlink.firstChild(named: "group")?.attrs["jid"] == "120363000000000020@g.us")
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "community-unlink-alias", "type": "result"]))
		try await unlinkTask.value
	}

	@Test("Baileys community invite aliases send invite and revoke stanzas")
	func baileysCommunityInviteAliasesSendInviteAndRevokeStanzas() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let acceptTask = Task {
			try await client.communityAcceptInvite("COM123", requestID: "community-accept-alias")
		}
		let acceptRequest = try await transport.waitForSentNode(at: 0)
		#expect(acceptRequest.firstChild(named: "invite")?.attrs["code"] == "COM123")
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-accept-alias", "type": "result"],
			content: .nodes([BinaryNode(tag: "community", attrs: ["jid": "120363000000000010@g.us"])])
		))
		#expect(try await acceptTask.value == "120363000000000010@g.us")

		let revokeTask = Task {
			try await client.communityRevokeInviteV4(
				"120363000000000010@g.us",
				"111@s.whatsapp.net",
				requestID: "community-revoke-alias"
			)
		}
		let revokeRequest = try await transport.waitForSentNode(at: 1)
		let revoke = try #require(revokeRequest.firstChild(named: "revoke"))
		#expect(revoke.firstChild(named: "participant")?.attrs["jid"] == "111@s.whatsapp.net")
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "community-revoke-alias", "type": "result"]))
		#expect(try await revokeTask.value)
	}
}
