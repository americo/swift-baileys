import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client group aliases")
struct WhatsAppClientGroupAliasTests {
	@Test("Baileys group create alias sends create stanza")
	func baileysGroupCreateAliasSendsCreateStanza() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupCreate(
				"Swift Group",
				["111@s.whatsapp.net", "222@s.whatsapp.net"],
				requestID: "group-create-alias",
				groupKey: "group-key-alias"
			)
		}
		let request = try await transport.waitForSentNode()
		let create = try #require(request.firstChild(named: "create"))
		#expect(request.attrs["id"] == "group-create-alias")
		#expect(create.attrs["subject"] == "Swift Group")
		#expect(create.attrs["key"] == "group-key-alias")
		#expect(create.children(named: "participant").map { $0.attrs["jid"] } == [
			"111@s.whatsapp.net",
			"222@s.whatsapp.net"
		])

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "group-create-alias", "type": "result"],
			content: .nodes([groupNode()])
		))
		#expect(try await task.value.id == "120363000000000000@g.us")
	}

	@Test("Baileys group accept invite alias sends invite code")
	func baileysGroupAcceptInviteAliasSendsInviteCode() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupAcceptInvite("ABC123", requestID: "group-accept-alias")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "group-accept-alias")
		#expect(request.attrs["to"] == "@g.us")
		#expect(request.firstChild(named: "invite")?.attrs["code"] == "ABC123")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "group-accept-alias", "type": "result"],
			content: .nodes([BinaryNode(tag: "group", attrs: ["jid": "120363000000000000@g.us"])])
		))
		#expect(try await task.value == "120363000000000000@g.us")
	}

	@Test("Baileys group invite info alias fetches metadata")
	func baileysGroupInviteInfoAliasFetchesMetadata() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupGetInviteInfo("ABC123", requestID: "group-info-alias")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "group-info-alias")
		#expect(request.attrs["to"] == "@g.us")
		#expect(request.attrs["type"] == "get")
		#expect(request.firstChild(named: "invite")?.attrs["code"] == "ABC123")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "group-info-alias", "type": "result"],
			content: .nodes([groupNode(subject: "Invite Group")])
		))
		#expect(try await task.value.subject == "Invite Group")
	}

	@Test("Baileys group revoke invite v4 alias sends revoke participant")
	func baileysGroupRevokeInviteV4AliasSendsRevokeParticipant() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupRevokeInviteV4(
				"120363000000000000@g.us",
				"111@s.whatsapp.net",
				requestID: "group-revoke-v4-alias"
			)
		}
		let request = try await transport.waitForSentNode()
		let revoke = try #require(request.firstChild(named: "revoke"))
		#expect(request.attrs["id"] == "group-revoke-v4-alias")
		#expect(request.attrs["to"] == "120363000000000000@g.us")
		#expect(revoke.firstChild(named: "participant")?.attrs["jid"] == "111@s.whatsapp.net")

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "group-revoke-v4-alias", "type": "result"]))
		#expect(try await task.value)
	}
}
