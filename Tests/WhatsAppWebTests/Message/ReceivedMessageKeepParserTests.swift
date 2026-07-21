import Testing
@testable import WhatsAppWeb

@Suite("Received message keep parser")
struct ReceivedMessageKeepParserTests {
	@Test("parses keep in chat messages")
	func parsesKeepInChatMessages() throws {
		var keep = Proto_Message.KeepInChatMessage()
		keep.key = targetKey()
		keep.keepType = .keepForAll
		keep.timestampMs = 1_700_444_555_000
		var message = Proto_Message()
		message.keepInChatMessage = keep

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .messageKeep(ReceivedMessageKeepContent(
			key: ReceivedMessageKey(
				remoteJID: "120363000000000000@g.us",
				fromMe: false,
				id: "KEEP_TARGET",
				participant: "258840000000@s.whatsapp.net"
			),
			action: .keepForAll,
			timestampMilliseconds: 1_700_444_555_000
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses undo keep in chat messages")
	func parsesUndoKeepInChatMessages() throws {
		var keep = Proto_Message.KeepInChatMessage()
		keep.key = targetKey()
		keep.keepType = .undoKeepForAll
		var message = Proto_Message()
		message.keepInChatMessage = keep

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .messageKeep(ReceivedMessageKeepContent(
			key: ReceivedMessageKey(
				remoteJID: "120363000000000000@g.us",
				fromMe: false,
				id: "KEEP_TARGET",
				participant: "258840000000@s.whatsapp.net"
			),
			action: .undoKeepForAll,
			timestampMilliseconds: nil
		)))
	}

	private func targetKey() -> Proto_MessageKey {
		var key = Proto_MessageKey()
		key.remoteJid = "120363000000000000@g.us"
		key.fromMe = false
		key.id = "KEEP_TARGET"
		key.participant = "258840000000@s.whatsapp.net"

		return key
	}
}
