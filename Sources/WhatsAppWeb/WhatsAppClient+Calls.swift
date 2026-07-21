import Foundation

extension WhatsAppClient {
	public func rejectCall(id callID: String, from callFrom: String) async throws {
		guard let meID = authenticationState?.credentials.me?.id else {
			throw WhatsAppClientError.missingAuthenticatedUser
		}

		try await sendNode(BinaryNode(
			tag: "call",
			attrs: ["from": meID, "to": callFrom],
			content: .nodes([
				BinaryNode(
					tag: "reject",
					attrs: ["call-id": callID, "call-creator": callFrom, "count": "0"]
				)
			])
		))
	}
}
