import Foundation

extension WhatsAppClient {
	func handleMessageAckNode(_ node: BinaryNode) async -> Bool {
		guard node.tag == "ack", node.attrs["class"] == "message" else {
			return false
		}

		guard node.attrs["error"] != nil else {
			return true
		}

		if node.attrs["error"] == "463" {
			await recoverTrustedContactTokenAfterAccountRestriction(from: node.attrs["from"])
		}

		eventContinuation.yield(.messagesUpdated([
			ReceivedMessageUpdate(
				key: WhatsAppMessageKey(remoteJID: node.attrs["from"], fromMe: true, id: node.attrs["id"]),
				status: .error,
				timestamp: nil
			)
		]))
		return true
	}
}
