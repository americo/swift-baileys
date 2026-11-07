import Foundation

extension WhatsAppClient {
	func sendGroupMessage(
		to destinationJID: String,
		message: Proto_Message,
		messageID: String?,
		additionalAttributes: [String: String] = [:],
		additionalNodes: [BinaryNode] = [],
		useUserDevicesCache: Bool = true
	) async throws -> String {
		guard let messageEncryptor else {
			throw WhatsAppClientError.missingMessageEncryptor
		}

		guard let groupMessageEncryptor else {
			throw WhatsAppClientError.missingGroupMessageEncryptor
		}

		guard let messageDeviceResolver else {
			throw WhatsAppClientError.missingMessageDeviceResolver
		}

		guard let signalSessionPreparer else {
			throw WhatsAppClientError.missingSignalSessionPreparer
		}

		guard let me = authenticationState?.credentials.me?.id else {
			throw WhatsAppClientError.missingAuthenticatedUser
		}

		let metadata = try await groupMetadata(destinationJID)
		var recipientDeviceJIDs: [String] = []
		let meLID = authenticationState?.credentials.me?.lid
		for participant in metadata.participants
		where !OwnDeviceAddressing.isOwnUser(participant.id, localJID: me, localLID: meLID) {
			recipientDeviceJIDs.append(contentsOf: try await messageDeviceResolver.deviceJIDs(
				for: participant.id,
				useCache: useUserDevicesCache
			))
		}
		// Our other devices need the sender key too, or they cannot read what this device sends.
		if !recipientDeviceJIDs.isEmpty {
			recipientDeviceJIDs += await ownDeviceJIDsForFanOut(lidAddressed: metadata.addressingMode == .lid)
		}

		_ = try await signalSessionPreparer.assertSessions(for: recipientDeviceJIDs, force: false)
		let resolvedMessageID = try messageID ?? messageIDGenerator.generateV2(userID: me)
		var relayAttributes = additionalAttributes
		relayAttributes["addressing_mode"] = metadata.addressingMode.rawValue
		if let ephemeralDuration = metadata.ephemeralDuration, ephemeralDuration > 0 {
			relayAttributes["expiration"] = String(ephemeralDuration)
		}

		let senderJID = metadata.addressingMode == .lid ? authenticationState?.credentials.me?.lid ?? me : me
		let stanza = try await MessageRelayBuilder(
			encoder: messageEncoder,
			encryptor: messageEncryptor,
			groupEncryptor: groupMessageEncryptor
		).buildGroupMessageStanza(
			to: destinationJID,
			messageID: resolvedMessageID,
			message: message,
			senderJID: senderJID,
			senderKeyRecipientDeviceJIDs: recipientDeviceJIDs,
			additionalAttributes: relayAttributes,
			additionalNodes: additionalNodes
		)
		try await sendNode(stanza)
		cacheRecentSentMessage(
			destinationJID: destinationJID,
			id: resolvedMessageID,
			message: message,
			additionalNodes: additionalNodes
		)
		return resolvedMessageID
	}
}
