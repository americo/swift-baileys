import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client profile aliases")
struct WhatsAppClientProfileAliasTests {
	@Test("Baileys profile picture Url alias queries profile picture URL")
	func baileysProfilePictureUrlAliasQueriesProfilePictureURL() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.profilePictureUrl(for: "258840000000@c.us", type: .image, requestID: "picture-alias-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "picture-alias-1")
		#expect(request.attrs["target"] == "258840000000@s.whatsapp.net")
		#expect(request.attrs["xmlns"] == "w:profile:picture")
		#expect(request.firstChild(named: "picture")?.attrs["type"] == "image")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "picture-alias-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "picture", attrs: ["url": "https://mmg.whatsapp.net/profile-alias.jpg"])
			])
		))
		#expect(try await task.value == "https://mmg.whatsapp.net/profile-alias.jpg")
	}

	@Test("Baileys fetch status alias uses USync status query")
	func baileysFetchStatusAliasUsesUSyncStatusQuery() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.fetchStatus("258840000000@c.us", requestID: "status-alias-1")
		}
		let request = try await transport.waitForSentNode()
		let usync = try #require(request.firstChild(named: "usync"))
		#expect(usync.attrs["sid"] == "status-alias-1")
		#expect(usync.firstChild(named: "query")?.firstChild(named: "status") != nil)
		#expect(usync.firstChild(named: "list")?.firstChild(named: "user")?.attrs["jid"] == "258840000000@s.whatsapp.net")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "status-alias-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "usync", content: .nodes([
					BinaryNode(tag: "list", content: .nodes([
						BinaryNode(
							tag: "user",
							attrs: ["jid": "258840000000@s.whatsapp.net"],
							content: .nodes([
								BinaryNode(tag: "status", attrs: ["t": "1700000000"], content: .data(Data("Available".utf8)))
							])
						)
					]))
				]))
			])
		))
		#expect(try await task.value == [
			ContactStatus(jid: "258840000000@s.whatsapp.net", status: "Available", setAt: Date(timeIntervalSince1970: 1_700_000_000))
		])
	}

	@Test("Baileys fetch disappearing duration alias uses USync disappearing query")
	func baileysFetchDisappearingDurationAliasUsesUSyncDisappearingQuery() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.fetchDisappearingDuration("258840000000@c.us", requestID: "disappearing-alias-1")
		}
		let request = try await transport.waitForSentNode()
		let usync = try #require(request.firstChild(named: "usync"))
		#expect(usync.attrs["sid"] == "disappearing-alias-1")
		#expect(usync.firstChild(named: "query")?.firstChild(named: "disappearing_mode") != nil)

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "disappearing-alias-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "usync", content: .nodes([
					BinaryNode(tag: "list", content: .nodes([
						BinaryNode(
							tag: "user",
							attrs: ["jid": "258840000000@s.whatsapp.net"],
							content: .nodes([
								BinaryNode(tag: "disappearing_mode", attrs: ["duration": "86400", "t": "1700000100"])
							])
						)
					]))
				]))
			])
		))
		#expect(try await task.value == [
			ContactDisappearingDuration(
				jid: "258840000000@s.whatsapp.net",
				duration: 86_400,
				setAt: Date(timeIntervalSince1970: 1_700_000_100)
			)
		])
	}
}
