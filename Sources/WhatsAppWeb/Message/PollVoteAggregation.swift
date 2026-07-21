import CryptoKit
import Foundation

public struct PollVoteUpdate: Equatable, Sendable {
	public let pollUpdateMessageKey: WhatsAppMessageKey
	public let selectedOptionHashes: [Data]

	public init(pollUpdateMessageKey: WhatsAppMessageKey, selectedOptionHashes: [Data]) {
		self.pollUpdateMessageKey = pollUpdateMessageKey
		self.selectedOptionHashes = selectedOptionHashes
	}
}

public struct PollVoteAggregation: Equatable, Sendable {
	public let name: String
	public let voters: [String]

	public init(name: String, voters: [String]) {
		self.name = name
		self.voters = voters
	}
}

public enum PollVoteAggregator {
	public static func aggregateVotes(
		in poll: ReceivedPollCreationContent?,
		updates: [PollVoteUpdate],
		meID: String = "me"
	) -> [PollVoteAggregation] {
		var order: [Data] = []
		var buckets: [Data: PollVoteAggregation] = [:]

		for option in poll?.options ?? [] {
			let name = option.name ?? ""
			let hash = Data(SHA256.hash(data: Data(name.utf8)))
			order.append(hash)
			buckets[hash] = PollVoteAggregation(name: name, voters: [])
		}

		for update in updates where !update.selectedOptionHashes.isEmpty {
			let voter = MessageKeyAuthor.author(for: update.pollUpdateMessageKey, meID: meID)

			for hash in update.selectedOptionHashes {
				if buckets[hash] == nil {
					order.append(hash)
					buckets[hash] = PollVoteAggregation(name: "Unknown", voters: [])
				}

				guard let bucket = buckets[hash] else {
					continue
				}

				buckets[hash] = PollVoteAggregation(name: bucket.name, voters: bucket.voters + [voter])
			}
		}

		return order.compactMap { buckets[$0] }
	}
}
