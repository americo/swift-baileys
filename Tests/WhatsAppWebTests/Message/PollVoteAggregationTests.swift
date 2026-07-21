import CryptoKit
import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Poll vote aggregation")
struct PollVoteAggregationTests {
	@Test("aggregates poll voters by selected option hashes")
	func aggregatesPollVotersBySelectedOptionHashes() {
		let poll = ReceivedPollCreationContent(
			name: "Runtime",
			options: [
				ReceivedPollOption(name: "Swift", hash: nil),
				ReceivedPollOption(name: "TypeScript", hash: nil)
			],
			selectableOptionsCount: 1,
			encryptedKey: nil,
			contentType: .text,
			pollType: .poll,
			correctAnswer: nil
		)

		let result = PollVoteAggregator.aggregateVotes(
			in: poll,
			updates: [
				update(remoteJID: "111@s.whatsapp.net", selectedOptionHashes: [optionHash("Swift")]),
				update(
					remoteJID: "group@g.us",
					participant: "222@s.whatsapp.net",
					selectedOptionHashes: [optionHash("TypeScript")]
				),
				update(remoteJID: "333@s.whatsapp.net", fromMe: true, selectedOptionHashes: [optionHash("Swift")]),
				update(remoteJID: "444@s.whatsapp.net", selectedOptionHashes: [Data([0x99])]),
				update(remoteJID: "555@s.whatsapp.net", selectedOptionHashes: []),
				update(
					remoteJID: "group@g.us",
					participant: "666@s.whatsapp.net",
					participantAlt: "666@lid",
					selectedOptionHashes: [optionHash("TypeScript")]
				)
			],
			meID: "999@s.whatsapp.net"
		)

		#expect(result == [
			PollVoteAggregation(name: "Swift", voters: ["111@s.whatsapp.net", "999@s.whatsapp.net"]),
			PollVoteAggregation(name: "TypeScript", voters: ["222@s.whatsapp.net", "666@lid"]),
			PollVoteAggregation(name: "Unknown", voters: ["444@s.whatsapp.net"])
		])
	}

	private func update(
		remoteJID: String,
		participant: String? = nil,
		participantAlt: String? = nil,
		fromMe: Bool = false,
		selectedOptionHashes: [Data]
	) -> PollVoteUpdate {
		PollVoteUpdate(
			pollUpdateMessageKey: WhatsAppMessageKey(
				remoteJID: remoteJID,
				fromMe: fromMe,
				id: "poll-update-id",
				participant: participant,
				participantAlt: participantAlt
			),
			selectedOptionHashes: selectedOptionHashes
		)
	}

	private func optionHash(_ name: String) -> Data {
		Data(SHA256.hash(data: Data(name.utf8)))
	}
}
