import Foundation

public enum WhatsAppClientPollVoteError: Error, Equatable, Sendable {
	case missingPollMessageID
}

extension WhatsAppClient {
	public func configurePollVoteContextResolver(_ resolver: (any PollVoteContextResolving)?) {
		pollVoteContextResolver = resolver
	}

	/// Replaces this account's vote on a poll. No options takes the vote back.
	/// `pollCreatorJID` and `voterJID` must be written the way everyone else will read them:
	/// without a device, in the addressing the chat uses.
	public func sendPollVoteMessage(
		to destinationJID: String,
		poll: WhatsAppMessageKey,
		selectedOptions: [String],
		pollCreatorJID: String,
		voterJID: String,
		pollEncKey: Data,
		messageID: String? = nil,
		cipher: PollVoteCipher = PollVoteCipher()
	) async throws -> String {
		guard let pollMessageID = poll.id else {
			throw WhatsAppClientPollVoteError.missingPollMessageID
		}
		let vote = try cipher.encrypt(
			selectedOptionHashes: selectedOptions.map(PollVoteCipher.optionHash),
			pollMessageID: pollMessageID,
			pollCreatorJID: pollCreatorJID,
			voterJID: voterJID,
			pollEncKey: pollEncKey
		)
		var update = Proto_Message.PollUpdateMessage()
		var pollKey = Proto_MessageKey()
		pollKey.remoteJid = destinationJID
		pollKey.fromMe = poll.fromMe
		pollKey.id = pollMessageID
		if let participant = poll.participant {
			pollKey.participant = participant
		}
		update.pollCreationMessageKey = pollKey
		update.vote = vote
		update.senderTimestampMs = Int64(Date().timeIntervalSince1970 * 1000)
		var message = Proto_Message()
		message.pollUpdateMessage = update
		return try await sendResolvedMessage(
			to: destinationJID,
			message: message,
			messageID: messageID,
			additionalNodes: [BinaryNode(tag: "meta", attrs: ["polltype": "vote"])]
		)
	}
}
