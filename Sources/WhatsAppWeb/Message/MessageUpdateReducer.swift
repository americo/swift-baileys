import Foundation

public enum MessageKeyAuthor {
	public static func author(for key: WhatsAppMessageKey?, meID: String = "me") -> String {
		guard let key else {
			return ""
		}

		if key.fromMe {
			return meID
		}

		return key.participantAlt ?? key.remoteJIDAlt ?? key.participant ?? key.remoteJID ?? ""
	}
}

public enum MessageUpdateReducer {
	public static func applyingReceipt(
		_ receipt: ReceivedMessageUserReceipt,
		to receipts: [ReceivedMessageUserReceipt]
	) -> [ReceivedMessageUserReceipt] {
		guard let existingIndex = receipts.firstIndex(where: { $0.userJID == receipt.userJID }) else {
			return receipts + [receipt]
		}

		var updated = receipts
		updated[existingIndex] = receipt
		return updated
	}

	public static func applyingReaction(
		_ update: ReceivedMessageReactionUpdate,
		to reactions: [ReceivedMessageReactionUpdate],
		meID: String = "me"
	) -> [ReceivedMessageReactionUpdate] {
		let author = MessageKeyAuthor.author(for: update.reactionMessageKey, meID: meID)
		let merged = ReceivedMessageReactionUpdate(
			key: update.key,
			reactionMessageKey: update.reactionMessageKey,
			text: update.text ?? "",
			groupingKey: update.groupingKey,
			senderTimestampMilliseconds: update.senderTimestampMilliseconds
		)

		return reactions.filter {
			MessageKeyAuthor.author(for: $0.reactionMessageKey, meID: meID) != author
		} + [merged]
	}

	public static func applyingPollVote(
		_ update: PollVoteUpdate,
		to updates: [PollVoteUpdate],
		meID: String = "me"
	) -> [PollVoteUpdate] {
		let author = MessageKeyAuthor.author(for: update.pollUpdateMessageKey, meID: meID)
		let existing = updates.filter {
			MessageKeyAuthor.author(for: $0.pollUpdateMessageKey, meID: meID) != author
		}

		return update.selectedOptionHashes.isEmpty ? existing : existing + [update]
	}

	public static func applyingEventResponse(
		_ update: ReceivedMessageEventResponseUpdate,
		to responses: [ReceivedMessageEventResponseUpdate],
		meID: String = "me"
	) -> [ReceivedMessageEventResponseUpdate] {
		let author = MessageKeyAuthor.author(for: update.eventResponseMessageKey, meID: meID)

		return responses.filter {
			MessageKeyAuthor.author(for: $0.eventResponseMessageKey, meID: meID) != author
		} + [update]
	}
}
