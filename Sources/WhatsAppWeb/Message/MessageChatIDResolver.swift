import Foundation

public enum MessageChatIDResolutionError: Error, Equatable, Sendable {
	case missingRemoteJID
	case missingBroadcastParticipant(remoteJID: String, fromMe: Bool)
}

public enum MessageChatIDResolver {
	public static func chatID(for key: WhatsAppMessageKey) throws -> String {
		guard let remoteJID = key.remoteJID else {
			throw MessageChatIDResolutionError.missingRemoteJID
		}

		if remoteJID.isBroadcastJID, !remoteJID.isStatusBroadcastJID, !key.fromMe {
			guard let participant = key.participant else {
				throw MessageChatIDResolutionError.missingBroadcastParticipant(
					remoteJID: remoteJID,
					fromMe: key.fromMe
				)
			}

			return participant
		}

		return remoteJID
	}
}
