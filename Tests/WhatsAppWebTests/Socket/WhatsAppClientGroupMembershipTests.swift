import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client group membership approvals")
struct WhatsAppClientGroupMembershipTests {
	@Test("requests pending membership approvals")
	func requestsPendingMembershipApprovals() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupRequestParticipantsList(
				"120363000000000000@g.us",
				requestID: "membership-list-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "membership-list-1")
		#expect(request.attrs["to"] == "120363000000000000@g.us")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "w:g2")
		#expect(request.firstChild(named: "membership_approval_requests") != nil)

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "membership-list-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "membership_approval_requests", content: .nodes([
					BinaryNode(tag: "membership_approval_request", attrs: [
						"jid": "111@s.whatsapp.net",
						"request_method": "invite_link",
						"t": "1700000000"
					]),
					BinaryNode(tag: "membership_approval_request", attrs: [
						"jid": "222@s.whatsapp.net",
						"request_method": "linked_group_join"
					])
				]))
			])
		))
		#expect(try await task.value == [
			GroupMembershipApprovalRequest(
				jid: "111@s.whatsapp.net",
				requestMethod: "invite_link",
				requestedAt: 1_700_000_000
			),
			GroupMembershipApprovalRequest(
				jid: "222@s.whatsapp.net",
				requestMethod: "linked_group_join",
				requestedAt: nil
			)
		])
	}

	@Test("updates pending membership approvals")
	func updatesPendingMembershipApprovals() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.groupRequestParticipantsUpdate(
				"120363000000000000@g.us",
				participants: ["111@s.whatsapp.net", "222@s.whatsapp.net"],
				action: .approve,
				requestID: "membership-update-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "membership-update-1")
		#expect(request.attrs["to"] == "120363000000000000@g.us")
		#expect(request.attrs["type"] == "set")
		let action = try #require(
			request.firstChild(named: "membership_requests_action")?.firstChild(named: "approve")
		)
		#expect(action.children(named: "participant").map { $0.attrs["jid"] } == [
			"111@s.whatsapp.net",
			"222@s.whatsapp.net"
		])

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "membership-update-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "membership_requests_action", content: .nodes([
					BinaryNode(tag: "approve", content: .nodes([
						BinaryNode(tag: "participant", attrs: ["jid": "111@s.whatsapp.net"]),
						BinaryNode(tag: "participant", attrs: ["jid": "222@s.whatsapp.net", "error": "403"])
					]))
				]))
			])
		))
		#expect(try await task.value == [
			GroupParticipantUpdateResult(jid: "111@s.whatsapp.net", status: "200"),
			GroupParticipantUpdateResult(jid: "222@s.whatsapp.net", status: "403")
		])
	}
}
