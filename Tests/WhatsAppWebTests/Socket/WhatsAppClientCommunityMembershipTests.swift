import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client community membership approvals")
struct WhatsAppClientCommunityMembershipTests {
	@Test("requests pending community membership approvals")
	func requestsPendingCommunityMembershipApprovals() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.communityRequestParticipantsList(
				"120363000000000010@g.us",
				requestID: "community-membership-list-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "community-membership-list-1")
		#expect(request.attrs["to"] == "120363000000000010@g.us")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "w:g2")
		#expect(request.firstChild(named: "membership_approval_requests") != nil)

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-membership-list-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "membership_approval_requests", content: .nodes([
					BinaryNode(tag: "membership_approval_request", attrs: [
						"jid": "111@s.whatsapp.net",
						"request_method": "invite_link",
						"t": "1700000300"
					])
				]))
			])
		))
		#expect(try await task.value == [
			GroupMembershipApprovalRequest(
				jid: "111@s.whatsapp.net",
				requestMethod: "invite_link",
				requestedAt: 1_700_000_300
			)
		])
	}

	@Test("updates pending community membership approvals")
	func updatesPendingCommunityMembershipApprovals() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.communityRequestParticipantsUpdate(
				"120363000000000010@g.us",
				participants: ["111@s.whatsapp.net", "222@s.whatsapp.net"],
				action: .reject,
				requestID: "community-membership-update-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "community-membership-update-1")
		#expect(request.attrs["to"] == "120363000000000010@g.us")
		#expect(request.attrs["type"] == "set")
		let reject = try #require(
			request.firstChild(named: "membership_requests_action")?.firstChild(named: "reject")
		)
		#expect(reject.children(named: "participant").map { $0.attrs["jid"] } == [
			"111@s.whatsapp.net",
			"222@s.whatsapp.net"
		])

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "community-membership-update-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "membership_requests_action", content: .nodes([
					BinaryNode(tag: "reject", content: .nodes([
						BinaryNode(tag: "participant", attrs: ["jid": "111@s.whatsapp.net"]),
						BinaryNode(tag: "participant", attrs: ["jid": "222@s.whatsapp.net", "error": "404"])
					]))
				]))
			])
		))
		#expect(try await task.value == [
			GroupParticipantUpdateResult(jid: "111@s.whatsapp.net", status: "200"),
			GroupParticipantUpdateResult(jid: "222@s.whatsapp.net", status: "404")
		])
	}
}
