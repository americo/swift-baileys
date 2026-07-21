import Testing
@testable import WhatsAppWeb

@Suite("Received message poll result parser")
struct ReceivedMessagePollResultParserTests {
	@Test("parses poll result snapshots")
	func parsesPollResultSnapshots() throws {
		var morning = Proto_Message.PollResultSnapshotMessage.PollVote()
		morning.optionName = "Morning"
		morning.optionVoteCount = 7
		var evening = Proto_Message.PollResultSnapshotMessage.PollVote()
		evening.optionName = "Evening"
		evening.optionVoteCount = 3
		var snapshot = Proto_Message.PollResultSnapshotMessage()
		snapshot.name = "Launch window"
		snapshot.pollVotes = [morning, evening]
		snapshot.pollType = .quiz
		var message = Proto_Message()
		message.pollResultSnapshotMessage = snapshot

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .pollResultSnapshot(ReceivedPollResultSnapshotContent(
			name: "Launch window",
			votes: [
				ReceivedPollResultVote(optionName: "Morning", voteCount: 7),
				ReceivedPollResultVote(optionName: "Evening", voteCount: 3)
			],
			pollType: .quiz
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses poll result snapshot v3")
	func parsesPollResultSnapshotV3() throws {
		var option = Proto_Message.PollResultSnapshotMessage.PollVote()
		option.optionName = "Maputo"
		option.optionVoteCount = 5
		var snapshot = Proto_Message.PollResultSnapshotMessage()
		snapshot.name = "Office"
		snapshot.pollVotes = [option]
		snapshot.pollType = .poll
		var message = Proto_Message()
		message.pollResultSnapshotMessageV3 = snapshot

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .pollResultSnapshot(ReceivedPollResultSnapshotContent(
			name: "Office",
			votes: [ReceivedPollResultVote(optionName: "Maputo", voteCount: 5)],
			pollType: .poll
		)))
	}
}
