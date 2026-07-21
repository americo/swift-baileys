import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Message update reducer")
struct MessageUpdateReducerTests {
	@Test("upserts receipts by user jid")
	func upsertsReceiptsByUserJID() {
		let existing = receipt(userJID: "111@s.whatsapp.net", receiptTimestamp: 1_000, readTimestamp: nil)
		let replacement = receipt(userJID: "111@s.whatsapp.net", receiptTimestamp: nil, readTimestamp: 2_000)
		let other = receipt(userJID: "222@s.whatsapp.net", receiptTimestamp: 1_500, readTimestamp: nil)

		let result = MessageUpdateReducer.applyingReceipt(replacement, to: [existing, other])

		#expect(result == [replacement, other])
		#expect(MessageUpdateReducer.applyingReceipt(
			receipt(userJID: "333@s.whatsapp.net", receiptTimestamp: 3_000, readTimestamp: nil),
			to: [existing]
		) == [
			existing,
			receipt(userJID: "333@s.whatsapp.net", receiptTimestamp: 3_000, readTimestamp: nil)
		])
	}

	@Test("resolves message key authors like Baileys")
	func resolvesMessageKeyAuthorsLikeBaileys() {
		#expect(MessageKeyAuthor.author(for: nil) == "")
		#expect(MessageKeyAuthor.author(for: key("chat@s.whatsapp.net", fromMe: true), meID: "me@s.whatsapp.net") == "me@s.whatsapp.net")
		#expect(MessageKeyAuthor.author(for: key("group@g.us", participant: "111@s.whatsapp.net", participantAlt: "111@lid")) == "111@lid")
		#expect(MessageKeyAuthor.author(for: key("222@s.whatsapp.net", remoteJIDAlt: "222@lid")) == "222@lid")
		#expect(MessageKeyAuthor.author(for: key("group@g.us", participant: "111@s.whatsapp.net")) == "111@s.whatsapp.net")
		#expect(MessageKeyAuthor.author(for: key("222@s.whatsapp.net")) == "222@s.whatsapp.net")
	}

	@Test("upserts reactions by author and normalizes missing text")
	func upsertsReactionsByAuthorAndNormalizesMissingText() {
		let existing = reaction(remoteJID: "group@g.us", participant: "111@s.whatsapp.net", text: "👍")
		let replacement = reaction(remoteJID: "group@g.us", participant: "111@s.whatsapp.net", text: nil)
		let other = reaction(remoteJID: "group@g.us", participant: "222@s.whatsapp.net", text: "🔥")

		let result = MessageUpdateReducer.applyingReaction(replacement, to: [existing, other])

		#expect(result.map { $0.text } == ["🔥", ""])
		#expect(result.map { $0.reactionMessageKey.participant } == ["222@s.whatsapp.net", "111@s.whatsapp.net"])
	}

	@Test("upserts poll votes by author and removes empty selections")
	func upsertsPollVotesByAuthorAndRemovesEmptySelections() {
		let existing = pollVote(remoteJID: "group@g.us", participant: "111@s.whatsapp.net", selectedOptionHashes: [Data([0x01])])
		let replacement = pollVote(remoteJID: "group@g.us", participant: "111@s.whatsapp.net", selectedOptionHashes: [Data([0x02])])
		let cleared = pollVote(remoteJID: "group@g.us", participant: "111@s.whatsapp.net", selectedOptionHashes: [])
		let other = pollVote(remoteJID: "group@g.us", participant: "222@s.whatsapp.net", selectedOptionHashes: [Data([0x03])])

		let replaced = MessageUpdateReducer.applyingPollVote(replacement, to: [existing, other])
		let clearedResult = MessageUpdateReducer.applyingPollVote(cleared, to: replaced)

		#expect(replaced.map(\.selectedOptionHashes) == [[Data([0x03])], [Data([0x02])]])
		#expect(clearedResult.map(\.selectedOptionHashes) == [[Data([0x03])]])
	}

	@Test("upserts event responses by author")
	func upsertsEventResponsesByAuthor() {
		let existing = eventResponse(remoteJID: "group@g.us", participant: "111@s.whatsapp.net", response: .going)
		let replacement = eventResponse(remoteJID: "group@g.us", participant: "111@s.whatsapp.net", response: .notGoing)
		let other = eventResponse(remoteJID: "group@g.us", participant: "222@s.whatsapp.net", response: .maybe)

		let result = MessageUpdateReducer.applyingEventResponse(replacement, to: [existing, other])

		#expect(result.compactMap { $0.response?.response } == [.maybe, .notGoing])
		#expect(result.map { $0.eventResponseMessageKey.participant } == ["222@s.whatsapp.net", "111@s.whatsapp.net"])
	}

	private func key(
		_ remoteJID: String,
		fromMe: Bool = false,
		participant: String? = nil,
		remoteJIDAlt: String? = nil,
		participantAlt: String? = nil
	) -> WhatsAppMessageKey {
		WhatsAppMessageKey(
			remoteJID: remoteJID,
			fromMe: fromMe,
			id: "message-id",
			participant: participant,
			remoteJIDAlt: remoteJIDAlt,
			participantAlt: participantAlt
		)
	}

	private func reaction(remoteJID: String, participant: String?, text: String?) -> ReceivedMessageReactionUpdate {
		ReceivedMessageReactionUpdate(
			key: key("target@s.whatsapp.net"),
			reactionMessageKey: key(remoteJID, participant: participant),
			text: text,
			groupingKey: nil,
			senderTimestampMilliseconds: nil
		)
	}

	private func pollVote(remoteJID: String, participant: String?, selectedOptionHashes: [Data]) -> PollVoteUpdate {
		PollVoteUpdate(
			pollUpdateMessageKey: key(remoteJID, participant: participant),
			selectedOptionHashes: selectedOptionHashes
		)
	}

	private func eventResponse(
		remoteJID: String,
		participant: String?,
		response: ReceivedEventResponseType
	) -> ReceivedMessageEventResponseUpdate {
		ReceivedMessageEventResponseUpdate(
			key: key("event@g.us"),
			eventResponseMessageKey: key(remoteJID, participant: participant),
			encryptedPayload: nil,
			encryptedIV: nil,
			response: ReceivedEventResponseContent(response: response, timestampMilliseconds: nil)
		)
	}

	private func receipt(
		userJID: String,
		receiptTimestamp: UInt64?,
		readTimestamp: UInt64?
	) -> ReceivedMessageUserReceipt {
		ReceivedMessageUserReceipt(
			userJID: userJID,
			receiptTimestamp: receiptTimestamp,
			readTimestamp: readTimestamp
		)
	}
}
