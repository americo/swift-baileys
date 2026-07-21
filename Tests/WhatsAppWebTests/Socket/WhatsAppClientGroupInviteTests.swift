import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client group invites")
struct WhatsAppClientGroupInviteTests {
	@Test("gets group metadata from an invite code")
	func getsGroupMetadataFromInviteCode() async throws {
		let transport = MockGroupInviteWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupGetInviteInfo(code: "ABC123", requestID: "invite-info-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "invite-info-1")
		#expect(request.attrs["to"] == "@g.us")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "w:g2")
		#expect(request.firstChild(named: "invite")?.attrs["code"] == "ABC123")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "invite-info-1", "type": "result"],
			content: .nodes([inviteGroupNode()])
		))
		let metadata = try await task.value

		#expect(metadata.id == "120363999999999999@g.us")
		#expect(metadata.subject == "Invite Group")
		#expect(metadata.size == 1)
	}

	@Test("revokes v4 group invite for an invited participant")
	func revokesV4GroupInviteForInvitedParticipant() async throws {
		let transport = MockGroupInviteWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupRevokeInviteV4(
				groupJID: "120363999999999999@g.us",
				invitedJID: "258840000000@s.whatsapp.net",
				requestID: "invite-v4-revoke-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "invite-v4-revoke-1")
		#expect(request.attrs["to"] == "120363999999999999@g.us")
		#expect(request.attrs["type"] == "set")
		let revoke = try #require(request.firstChild(named: "revoke"))
		#expect(revoke.firstChild(named: "participant")?.attrs["jid"] == "258840000000@s.whatsapp.net")

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "invite-v4-revoke-1", "type": "result"]))
		#expect(try await task.value == true)
	}

	@Test("accepts v4 group invite with invite metadata")
	func acceptsV4GroupInviteWithInviteMetadata() async throws {
		let transport = MockGroupInviteWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupAcceptInviteV4(
				groupJID: "120363999999999999@g.us",
				inviteCode: "INVITE123",
				inviteExpiration: 1_700_000_400,
				adminJID: "258840000000@s.whatsapp.net",
				requestID: "invite-v4-accept-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "invite-v4-accept-1")
		#expect(request.attrs["to"] == "120363999999999999@g.us")
		#expect(request.attrs["type"] == "set")
		let accept = try #require(request.firstChild(named: "accept"))
		#expect(accept.attrs["code"] == "INVITE123")
		#expect(accept.attrs["expiration"] == "1700000400")
		#expect(accept.attrs["admin"] == "258840000000@s.whatsapp.net")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: [
				"id": "invite-v4-accept-1",
				"type": "result",
				"from": "120363999999999999@g.us"
			]
		))
		#expect(try await task.value == "120363999999999999@g.us")
	}
}

private actor MockGroupInviteWebSocketTransport: WhatsAppWebSocketTransport {
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

private func inviteGroupNode() -> BinaryNode {
	BinaryNode(
		tag: "group",
		attrs: [
			"id": "120363999999999999",
			"subject": "Invite Group",
			"creation": "1700000000",
			"size": "1"
		],
		content: .nodes([
			BinaryNode(tag: "participant", attrs: ["jid": "258840000000@s.whatsapp.net"])
		])
	)
}
