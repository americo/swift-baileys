import Testing
@testable import WhatsAppWeb

@Suite("Received message future proof parser")
struct ReceivedMessageFutureProofParserTests {
	@Test("parses additional future proof envelopes")
	func parsesAdditionalFutureProofEnvelopes() throws {
		let inner = MessageContentBuilder.text("future wrapped")

		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.groupMentionedMessage = $1 })) == .text("future wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.botInvokeMessage = $1 })) == .text("future wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.eventCoverImage = $1 })) == .text("future wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.pollCreationOptionImageMessage = $1 })) == .text("future wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.statusAddYours = $1 })) == .text("future wrapped"))
	}
}
