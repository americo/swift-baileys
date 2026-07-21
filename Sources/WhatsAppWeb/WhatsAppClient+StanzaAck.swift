import Foundation

extension WhatsAppClient {
	@discardableResult
	public func sendMessageAck(_ node: BinaryNode, errorCode: Int? = nil) async throws -> BinaryNode {
		guard node.attrs["id"] != nil else {
			throw WhatsAppClientError.missingRequestID
		}
		guard node.attrs["from"] != nil else {
			throw WhatsAppClientError.missingMessageDestination
		}
		guard let ack = StanzaAck.build(
			for: node,
			errorCode: errorCode,
			meID: authenticationState?.credentials.me?.id
		) else {
			throw WhatsAppClientError.missingRequestID
		}

		try await sendNode(ack)
		return ack
	}
}
