import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client group member label updates")
struct WhatsAppClientGroupMemberLabelUpdateTests {
	@Test("group member label protocol messages emit member label updates before the envelope")
	func groupMemberLabelProtocolMessagesEmitMemberLabelUpdatesBeforeTheEnvelope() async throws {
		var label = Proto_MemberLabel()
		label.label = "team-a"
		label.labelTimestamp = 1_700_001_000
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .groupMemberLabelChange
		protocolMessage.memberLabel = label
		var message = Proto_Message()
		message.protocolMessage = protocolMessage
		let client = WhatsAppClient(messageDecryptor: GroupMemberLabelUpdateDecryptor(message: message))
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(groupMemberLabelUpdateNode())

		#expect(await events.next() == .groupMemberLabelUpdated(GroupMemberLabelUpdate(
			groupID: "120363000000000000@g.us",
			label: "team-a",
			participant: "456@s.whatsapp.net",
			participantAlt: "456@lid",
			messageTimestamp: 1_700_000_007
		)))
		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "label-envelope",
			from: "120363000000000000@g.us",
			timestamp: 1_700_000_007,
			content: .groupMemberLabelChange(ReceivedGroupMemberLabelChangeContent(
				label: "team-a",
				labelTimestamp: 1_700_001_000
			)),
			participant: "456@s.whatsapp.net"
		)))
	}
}

private struct GroupMemberLabelUpdateDecryptor: IncomingMessageDecrypting {
	let message: Proto_Message

	func decryptIncomingMessage(from node: BinaryNode) async throws -> Proto_Message? {
		message
	}
}

private func groupMemberLabelUpdateNode() -> BinaryNode {
	BinaryNode(
		tag: "message",
		attrs: [
			"id": "label-envelope",
			"from": "120363000000000000@g.us",
			"participant": "456@s.whatsapp.net",
			"participant_alt": "456@lid",
			"t": "1700000007"
		],
		content: .nodes([
			BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0xaa, 0xbb])))
		])
	)
}
