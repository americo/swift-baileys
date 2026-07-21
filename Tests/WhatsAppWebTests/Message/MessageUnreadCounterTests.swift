import Testing
@testable import WhatsAppWeb

@Suite("Message unread counter")
struct MessageUnreadCounterTests {
	@Test("increments unread for incoming messages without stubs")
	func incrementsUnreadForIncomingMessagesWithoutStubs() {
		let message = receivedMessage(fromMe: false)

		#expect(MessageUnreadCounter.shouldIncrementChatUnread(for: message))
	}

	@Test("increments unread when fromMe is missing")
	func incrementsUnreadWhenFromMeIsMissing() {
		let message = receivedMessage(fromMe: nil)

		#expect(MessageUnreadCounter.shouldIncrementChatUnread(for: message))
	}

	@Test("does not increment unread for own messages")
	func doesNotIncrementUnreadForOwnMessages() {
		let message = receivedMessage(fromMe: true)

		#expect(!MessageUnreadCounter.shouldIncrementChatUnread(for: message))
	}

	@Test("does not increment unread for stub messages")
	func doesNotIncrementUnreadForStubMessages() {
		let message = receivedMessage(
			fromMe: false,
			stub: ReceivedMessageStubContent(type: .groupChangeSubject, parameters: ["New subject"])
		)

		#expect(!MessageUnreadCounter.shouldIncrementChatUnread(for: message))
	}

	private func receivedMessage(
		fromMe: Bool?,
		stub: ReceivedMessageStubContent? = nil
	) -> ReceivedMessage {
		ReceivedMessage(
			id: "message-id",
			from: "123@s.whatsapp.net",
			timestamp: 1_720_000_000,
			content: stub.map(ReceivedMessageContent.stub) ?? .text("hello"),
			fromMe: fromMe,
			stub: stub
		)
	}
}
