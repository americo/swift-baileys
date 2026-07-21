public enum MessageCleaner {
	public static func cleaned(_ message: ReceivedMessage, meID: String, meLID: String) -> ReceivedMessage {
		let cleanedFrom = normalizedMessageJID(message.from)
		let cleanedParticipant = normalizedMessageJID(message.participant)
		let cleanedKeyParticipant = normalizedMessageJID(message.keyParticipant)
		let cleanedContent = cleanedContent(
			message.content,
			messageFromMe: message.fromMe,
			remoteJID: cleanedFrom,
			participant: cleanedKeyParticipant ?? cleanedParticipant,
			meID: meID,
			meLID: meLID
		)

		return ReceivedMessage(
			id: message.id,
			from: cleanedFrom,
			timestamp: message.timestamp,
			content: cleanedContent,
			fromMe: message.fromMe,
			participant: cleanedParticipant,
			keyParticipant: cleanedKeyParticipant,
			status: message.status,
			pushName: message.pushName,
			stub: message.stub
		)
	}

	private static func cleanedContent(
		_ content: ReceivedMessageContent,
		messageFromMe: Bool?,
		remoteJID: String?,
		participant: String?,
		meID: String,
		meLID: String
	) -> ReceivedMessageContent {
		switch content {
		case .reaction(let reaction):
			return .reaction(ReceivedReactionContent(
				key: reaction.key.map {
					cleanedNestedKey($0, messageFromMe: messageFromMe, remoteJID: remoteJID, participant: participant, meID: meID, meLID: meLID)
				},
				text: reaction.text,
				groupingKey: reaction.groupingKey,
				senderTimestampMilliseconds: reaction.senderTimestampMilliseconds
			))
		case .encryptedReaction(let reaction):
			return .encryptedReaction(ReceivedEncryptedReactionContent(
				targetMessageKey: reaction.targetMessageKey.map {
					cleanedNestedKey($0, messageFromMe: messageFromMe, remoteJID: remoteJID, participant: participant, meID: meID, meLID: meLID)
				},
				encryptedPayload: reaction.encryptedPayload,
				encryptedIV: reaction.encryptedIV
			))
		case .pollUpdate(let update):
			return .pollUpdate(ReceivedPollUpdateContent(
				pollCreationMessageKey: update.pollCreationMessageKey.map {
					cleanedNestedKey($0, messageFromMe: messageFromMe, remoteJID: remoteJID, participant: participant, meID: meID, meLID: meLID)
				},
				encryptedPayload: update.encryptedPayload,
				encryptedIV: update.encryptedIV,
				senderTimestampMilliseconds: update.senderTimestampMilliseconds
			))
		default:
			return content
		}
	}

	private static func cleanedNestedKey(
		_ key: ReceivedMessageKey,
		messageFromMe: Bool?,
		remoteJID: String?,
		participant: String?,
		meID: String,
		meLID: String
	) -> ReceivedMessageKey {
		guard messageFromMe != true else {
			return key
		}

		let normalizedKeyParticipant = normalizedMessageJID(key.participant)
		let normalizedFallbackParticipant = normalizedMessageJID(participant)
		let author = normalizedKeyParticipant ?? normalizedMessageJID(key.remoteJID)
		let fromMe = key.fromMe
			? false
			: JID.areSameUser(author, meID) || JID.areSameUser(author, meLID)

		return ReceivedMessageKey(
			remoteJID: remoteJID,
			fromMe: fromMe,
			id: key.id,
			participant: normalizedKeyParticipant ?? normalizedFallbackParticipant
		)
	}

	private static func normalizedMessageJID(_ jid: String?) -> String? {
		guard let parsed = JID(jid) else {
			return jid
		}

		if jid?.isHostedUserJID == true {
			return JID.encode(user: parsed.user, server: JIDServer.user.rawValue)
		}

		if jid?.isHostedLIDUserJID == true {
			return JID.encode(user: parsed.user, server: JIDServer.lid.rawValue)
		}

		return parsed.normalizedUser
	}
}
