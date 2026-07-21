import Testing
@testable import WhatsAppWeb

@Suite("Received message pin parser")
struct ReceivedMessagePinParserTests {
	@Test("parses pin in chat messages")
	func parsesPinInChatMessages() throws {
		var pin = Proto_Message.PinInChatMessage()
		pin.key = targetKey()
		pin.type = .pinForAll
		pin.senderTimestampMs = 1_700_333_444_000
		var message = Proto_Message()
		message.pinInChatMessage = pin

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .messagePin(ReceivedMessagePinContent(
			key: ReceivedMessageKey(
				remoteJID: "120363000000000000@g.us",
				fromMe: false,
				id: "PIN_TARGET",
				participant: "258840000000@s.whatsapp.net"
			),
			action: .pinForAll,
			senderTimestampMilliseconds: 1_700_333_444_000
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses unpin in chat messages")
	func parsesUnpinInChatMessages() throws {
		var pin = Proto_Message.PinInChatMessage()
		pin.key = targetKey()
		pin.type = .unpinForAll
		var message = Proto_Message()
		message.pinInChatMessage = pin

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .messagePin(ReceivedMessagePinContent(
			key: ReceivedMessageKey(
				remoteJID: "120363000000000000@g.us",
				fromMe: false,
				id: "PIN_TARGET",
				participant: "258840000000@s.whatsapp.net"
			),
			action: .unpinForAll,
			senderTimestampMilliseconds: nil
		)))
	}

	private func targetKey() -> Proto_MessageKey {
		var key = Proto_MessageKey()
		key.remoteJid = "120363000000000000@g.us"
		key.fromMe = false
		key.id = "PIN_TARGET"
		key.participant = "258840000000@s.whatsapp.net"

		return key
	}
}
