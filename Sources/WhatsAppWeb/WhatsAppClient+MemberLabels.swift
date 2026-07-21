import Foundation

extension WhatsAppClient {
	@discardableResult
	public func updateMemberLabel(
		_ jid: String,
		memberLabel: String,
		timestamp: Int64 = Int64(Date().timeIntervalSince1970),
		messageID: String? = nil
	) async throws -> String {
		var label = Proto_MemberLabel()
		label.label = String(memberLabel.prefix(30))
		label.labelTimestamp = timestamp

		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .groupMemberLabelChange
		protocolMessage.memberLabel = label

		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		return try await sendResolvedMessage(
			to: jid,
			message: message,
			messageID: messageID,
			additionalNodes: [
				BinaryNode(tag: "meta", attrs: [
					"tag_reason": "user_update",
					"appdata": "member_tag"
				])
			]
		)
	}
}
