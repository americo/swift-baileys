import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Message forward poll update content builder")
struct MessageForwardPollUpdateContentBuilderTests {
	@Test("forwards poll update messages as pass-through content")
	func forwardsPollUpdateMessagesAsPassThroughContent() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "258840000000@s.whatsapp.net"
		key.fromMe = false
		key.id = "3EB0POLL"
		key.participant = "258841111111@s.whatsapp.net"
		var vote = Proto_Message.PollEncValue()
		vote.encPayload = Data([0x01, 0x02, 0x03])
		vote.encIv = Data([0x04, 0x05, 0x06])
		var update = Proto_Message.PollUpdateMessage()
		update.pollCreationMessageKey = key
		update.vote = vote
		update.senderTimestampMs = 1_700_002_000_000
		var source = Proto_Message()
		source.pollUpdateMessage = update

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasPollUpdateMessage)
		#expect(message.pollUpdateMessage.pollCreationMessageKey.id == "3EB0POLL")
		#expect(message.pollUpdateMessage.vote.encPayload == Data([0x01, 0x02, 0x03]))
		#expect(message.pollUpdateMessage.vote.encIv == Data([0x04, 0x05, 0x06]))
		#expect(message.pollUpdateMessage.senderTimestampMs == 1_700_002_000_000)
	}

	@Test("forwards poll result snapshot messages as pass-through content")
	func forwardsPollResultSnapshotMessagesAsPassThroughContent() throws {
		var vote = Proto_Message.PollResultSnapshotMessage.PollVote()
		vote.optionName = "Morning"
		vote.optionVoteCount = 7
		var snapshot = Proto_Message.PollResultSnapshotMessage()
		snapshot.name = "Launch window"
		snapshot.pollVotes = [vote]
		snapshot.pollType = .quiz
		var source = Proto_Message()
		source.pollResultSnapshotMessage = snapshot

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasPollResultSnapshotMessage)
		#expect(message.pollResultSnapshotMessage.name == "Launch window")
		#expect(message.pollResultSnapshotMessage.pollVotes.map(\.optionName) == ["Morning"])
		#expect(message.pollResultSnapshotMessage.pollVotes.map(\.optionVoteCount) == [7])
		#expect(message.pollResultSnapshotMessage.pollType == .quiz)
	}
}
