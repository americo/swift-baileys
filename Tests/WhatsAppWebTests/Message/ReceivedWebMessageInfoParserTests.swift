import Testing
@testable import WhatsAppWeb

@Suite("Received web message info parser")
struct ReceivedWebMessageInfoParserTests {
	@Test("parses envelope metadata and message content")
	func parsesEnvelopeMetadataAndMessageContent() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "123@s.whatsapp.net"
		key.fromMe = true
		key.id = "msg-1"
		key.participant = "device@s.whatsapp.net"
		var info = Proto_WebMessageInfo()
		info.key = key
		info.message = MessageContentBuilder.text("hello")
		info.messageTimestamp = 1_714_000_000
		info.status = .read
		info.pushName = "Alice"
		info.participant = "participant@s.whatsapp.net"

		let message = try #require(ReceivedWebMessageInfoParser.parse(info))

		#expect(message == ReceivedMessage(
			id: "msg-1",
			from: "123@s.whatsapp.net",
			timestamp: 1_714_000_000,
			content: .text("hello"),
			fromMe: true,
			participant: "participant@s.whatsapp.net",
			keyParticipant: "device@s.whatsapp.net",
			status: .read,
			pushName: "Alice",
			stub: nil
		))
	}

	@Test("parses reactions stored on the message")
	func parsesStoredReactions() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "group@g.us"
		key.id = "msg-1"
		var authorKey = Proto_MessageKey()
		authorKey.remoteJid = "group@g.us"
		authorKey.fromMe = false
		authorKey.id = "reaction-1"
		authorKey.participant = "alice@s.whatsapp.net"
		var reaction = Proto_Reaction()
		reaction.key = authorKey
		reaction.text = "❤️"
		reaction.senderTimestampMs = 1_714_000_000_000
		var info = Proto_WebMessageInfo()
		info.key = key
		info.message = MessageContentBuilder.text("hello")
		info.reactions = [reaction]

		let message = try #require(ReceivedWebMessageInfoParser.parse(info))

		#expect(message.reactions == [ReceivedReactionContent(
			key: ReceivedMessageKey(remoteJID: "group@g.us", fromMe: false, id: "reaction-1", participant: "alice@s.whatsapp.net"),
			text: "❤️",
			groupingKey: nil,
			senderTimestampMilliseconds: 1_714_000_000_000
		)])
	}

	@Test("parses stub-only system messages")
	func parsesStubOnlySystemMessages() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "group@g.us"
		key.id = "stub-1"
		var info = Proto_WebMessageInfo()
		info.key = key
		info.messageTimestamp = 1_714_000_100
		info.messageStubType = .groupParticipantAdd
		info.messageStubParameters = ["{\"jid\":\"123@s.whatsapp.net\"}"]

		let message = try #require(ReceivedWebMessageInfoParser.parse(info))

		#expect(message.content == .stub(ReceivedMessageStubContent(
			type: .groupParticipantAdd,
			parameters: ["{\"jid\":\"123@s.whatsapp.net\"}"]
		)))
		#expect(message.stub == ReceivedMessageStubContent(
			type: .groupParticipantAdd,
			parameters: ["{\"jid\":\"123@s.whatsapp.net\"}"]
		))
	}

	@Test("preserves unrecognized status and stub raw values")
	func preservesUnrecognizedStatusAndStubRawValues() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "123@s.whatsapp.net"
		key.id = "raw-1"
		var info = Proto_WebMessageInfo()
		info.key = key
		info.status = .UNRECOGNIZED(99)
		info.messageStubType = .UNRECOGNIZED(999)

		let message = try #require(ReceivedWebMessageInfoParser.parse(info))

		#expect(message.status == .unrecognized(99))
		#expect(message.stub?.type == ReceivedMessageStubType(rawValue: 999))
	}
}
