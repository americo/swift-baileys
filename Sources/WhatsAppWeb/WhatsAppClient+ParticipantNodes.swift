import Foundation

public struct BaileysParticipantNodesResult: Equatable, Sendable {
	public let nodes: [BinaryNode]
	public let shouldIncludeDeviceIdentity: Bool

	public init(nodes: [BinaryNode], shouldIncludeDeviceIdentity: Bool) {
		self.nodes = nodes
		self.shouldIncludeDeviceIdentity = shouldIncludeDeviceIdentity
	}
}

extension WhatsAppClient {
	public func createParticipantNodes(
		recipientJIDs: [String],
		encodedMessage: Data,
		extraAttributes: [String: String] = [:],
		encodedDeviceSentMessage: Data? = nil
	) async throws -> BaileysParticipantNodesResult {
		guard let messageEncryptor else {
			throw WhatsAppClientError.missingMessageEncryptor
		}

		let result = try await MessageRelayBuilder(
			encoder: messageEncoder,
			encryptor: messageEncryptor
		).createParticipantNodes(
			recipientDeviceJIDs: recipientJIDs,
			message: Proto_Message(serializedBytes: encodedMessage),
			deviceSentMessage: try encodedDeviceSentMessage.map { try Proto_Message(serializedBytes: $0) },
			localJID: authenticationState?.credentials.me?.id,
			localLID: authenticationState?.credentials.me?.lid,
			extraAttributes: extraAttributes
		)
		return BaileysParticipantNodesResult(
			nodes: result.nodes,
			shouldIncludeDeviceIdentity: result.shouldIncludeDeviceIdentity
		)
	}
}
