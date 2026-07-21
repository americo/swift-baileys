import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client community invite v4")
struct WhatsAppClientCommunityInviteV4Tests {
	@Test("accepts a community invite v4 with invite metadata")
	func acceptsCommunityInviteV4WithInviteMetadata() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.communityAcceptInviteV4(
				groupJID: "120363000000000010@g.us",
				inviteCode: "INVITE123",
				inviteExpiration: 1_700_000_400,
				adminJID: "111@s.whatsapp.net",
				requestID: "community-accept-v4-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "community-accept-v4-1")
		#expect(request.attrs["to"] == "120363000000000010@g.us")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "w:g2")
		let accept = try #require(request.firstChild(named: "accept"))
		#expect(accept.attrs["code"] == "INVITE123")
		#expect(accept.attrs["expiration"] == "1700000400")
		#expect(accept.attrs["admin"] == "111@s.whatsapp.net")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: [
				"id": "community-accept-v4-1",
				"type": "result",
				"from": "120363000000000010@g.us"
			]
		))
		#expect(try await task.value == "120363000000000010@g.us")
	}
}
