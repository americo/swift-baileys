import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message poll variant parser")
struct ReceivedMessagePollVariantParserTests {
	@Test("parses poll creation message variants")
	func parsesPollCreationMessageVariants() throws {
		let expected = ReceivedMessageContent.pollCreation(ReceivedPollCreationContent(
			name: "Launch window",
			options: [
				ReceivedPollOption(name: "Morning", hash: "am"),
				ReceivedPollOption(name: "Evening", hash: "pm")
			],
			selectableOptionsCount: 1,
			encryptedKey: Data([0x01, 0x02, 0x03]),
			contentType: .text,
			pollType: .quiz,
			correctAnswer: ReceivedPollOption(name: "Morning", hash: "am")
		))

		for message in pollVariantMessages() {
			let content = try #require(ReceivedMessageContentParser.parse(message))
			#expect(content == expected)
			#expect(try content.mediaDownloadRequest() == nil)
		}
	}

	private func pollVariantMessages() -> [Proto_Message] {
		let poll = pollCreation()
		var v2 = Proto_Message()
		v2.pollCreationMessageV2 = poll
		var v3 = Proto_Message()
		v3.pollCreationMessageV3 = poll
		var v4Inner = Proto_Message()
		v4Inner.pollCreationMessage = poll
		var v4Envelope = Proto_Message.FutureProofMessage()
		v4Envelope.message = v4Inner
		var v4 = Proto_Message()
		v4.pollCreationMessageV4 = v4Envelope
		var v5 = Proto_Message()
		v5.pollCreationMessageV5 = poll

		return [v2, v3, v4, v5]
	}

	private func pollCreation() -> Proto_Message.PollCreationMessage {
		var morning = Proto_Message.PollCreationMessage.Option()
		morning.optionName = "Morning"
		morning.optionHash = "am"
		var evening = Proto_Message.PollCreationMessage.Option()
		evening.optionName = "Evening"
		evening.optionHash = "pm"
		var poll = Proto_Message.PollCreationMessage()
		poll.name = "Launch window"
		poll.options = [morning, evening]
		poll.selectableOptionsCount = 1
		poll.encKey = Data([0x01, 0x02, 0x03])
		poll.pollContentType = .text
		poll.pollType = .quiz
		poll.correctAnswer = morning

		return poll
	}
}
