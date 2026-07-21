import Foundation

extension WhatsAppClient {
	public func requestMessageHistory(
		count: Int32,
		oldestMessageKey: WhatsAppMessageKey,
		oldestMessageTimestampMilliseconds: Int64,
		messageID: String? = nil
	) async throws -> String {
		guard let meJID = authenticationState?.credentials.me?.id else {
			throw WhatsAppClientError.missingAuthenticationState
		}

		return try await sendResolvedMessage(
			to: JID(meJID)?.normalizedUser ?? meJID,
			message: MessageContentBuilder.peerDataHistorySyncRequest(
				count: count,
				oldestMessageKey: oldestMessageKey,
				oldestMessageTimestampMilliseconds: oldestMessageTimestampMilliseconds
			),
			messageID: messageID,
			additionalAttributes: ["category": "peer", "push_priority": "high_force"],
			additionalNodes: [BinaryNode(tag: "meta", attrs: ["appdata": "default"])]
		)
	}

	public func fetchMessageHistory(
		count: Int32,
		oldestMessageKey: WhatsAppMessageKey,
		oldestMessageTimestampMilliseconds: Int64,
		messageID: String? = nil
	) async throws -> String {
		try await requestMessageHistory(
			count: count,
			oldestMessageKey: oldestMessageKey,
			oldestMessageTimestampMilliseconds: oldestMessageTimestampMilliseconds,
			messageID: messageID
		)
	}

	public func requestPlaceholderResend(
		for messageKey: WhatsAppMessageKey,
		messageID: String? = nil
	) async throws -> String {
		guard let meJID = authenticationState?.credentials.me?.id else {
			throw WhatsAppClientError.missingAuthenticationState
		}

		return try await sendResolvedMessage(
			to: JID(meJID)?.normalizedUser ?? meJID,
			message: MessageContentBuilder.peerDataPlaceholderResendRequest(messageKey: messageKey),
			messageID: messageID,
			additionalAttributes: ["category": "peer", "push_priority": "high_force"],
			additionalNodes: [BinaryNode(tag: "meta", attrs: ["appdata": "default"])]
		)
	}
}

extension MessageContentBuilder {
	static func peerDataHistorySyncRequest(
		count: Int32,
		oldestMessageKey: WhatsAppMessageKey,
		oldestMessageTimestampMilliseconds: Int64
	) -> Proto_Message {
		var request = Proto_Message.PeerDataOperationRequestMessage.HistorySyncOnDemandRequest()
		if let remoteJID = oldestMessageKey.remoteJID {
			request.chatJid = remoteJID
		}

		request.oldestMsgFromMe = oldestMessageKey.fromMe
		if let id = oldestMessageKey.id {
			request.oldestMsgID = id
		}

		request.oldestMsgTimestampMs = oldestMessageTimestampMilliseconds
		request.onDemandMsgCount = count

		var peerDataRequest = Proto_Message.PeerDataOperationRequestMessage()
		peerDataRequest.historySyncOnDemandRequest = request
		peerDataRequest.peerDataOperationRequestType = .historySyncOnDemand

		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.peerDataOperationRequestMessage = peerDataRequest
		protocolMessage.type = .peerDataOperationRequestMessage

		var message = Proto_Message()
		message.protocolMessage = protocolMessage
		return message
	}

	static func peerDataPlaceholderResendRequest(messageKey: WhatsAppMessageKey) -> Proto_Message {
		var protoKey = Proto_MessageKey()
		if let remoteJID = messageKey.remoteJID {
			protoKey.remoteJid = remoteJID
		}

		protoKey.fromMe = messageKey.fromMe
		if let id = messageKey.id {
			protoKey.id = id
		}

		if let participant = messageKey.participant {
			protoKey.participant = participant
		}

		var request = Proto_Message.PeerDataOperationRequestMessage.PlaceholderMessageResendRequest()
		request.messageKey = protoKey

		var peerDataRequest = Proto_Message.PeerDataOperationRequestMessage()
		peerDataRequest.placeholderMessageResendRequest = [request]
		peerDataRequest.peerDataOperationRequestType = .placeholderMessageResend

		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.peerDataOperationRequestMessage = peerDataRequest
		protocolMessage.type = .peerDataOperationRequestMessage

		var message = Proto_Message()
		message.protocolMessage = protocolMessage
		return message
	}
}
