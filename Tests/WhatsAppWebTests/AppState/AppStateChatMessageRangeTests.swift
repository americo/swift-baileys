import Testing
@testable import WhatsAppWeb

@Suite("App-state chat message range")
struct AppStateChatMessageRangeTests {
	@Test("builds proto range from public chat range messages")
	func buildsProtoRangeFromPublicChatRangeMessages() throws {
		let range = AppStateChatMessageRange(messages: [
			AppStateChatRangeMessage(
				key: WhatsAppMessageKey(
					remoteJID: "123@g.us",
					fromMe: false,
					id: "message-1",
					participant: "456:1@s.whatsapp.net"
				),
				timestamp: 60
			)
		])

		let proto = try range.proto()

		#expect(proto.lastMessageTimestamp == 60)
		#expect(proto.messages.first?.timestamp == 60)
		#expect(proto.messages.first?.key.remoteJid == "123@g.us")
		#expect(proto.messages.first?.key.id == "message-1")
		#expect(proto.messages.first?.key.participant == "456@s.whatsapp.net")
	}

	@Test("rejects group range messages without participant")
	func rejectsGroupRangeMessagesWithoutParticipant() throws {
		let range = AppStateChatMessageRange(messages: [
			AppStateChatRangeMessage(
				key: WhatsAppMessageKey(remoteJID: "123@g.us", fromMe: false, id: "message-1"),
				timestamp: 60
			)
		])

		#expect(throws: AppStateChatMessageRangeError.expectedGroupParticipant) {
			try range.proto()
		}
	}

	@Test("rejects range messages without complete key")
	func rejectsRangeMessagesWithoutCompleteKey() throws {
		let range = AppStateChatMessageRange(messages: [
			AppStateChatRangeMessage(
				key: WhatsAppMessageKey(remoteJID: nil, fromMe: true, id: "message-1"),
				timestamp: 60
			)
		])

		#expect(throws: AppStateChatMessageRangeError.incompleteKey) {
			try range.proto()
		}
	}

	@Test("rejects range messages without timestamp")
	func rejectsRangeMessagesWithoutTimestamp() throws {
		let range = AppStateChatMessageRange(messages: [
			AppStateChatRangeMessage(
				key: WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: true, id: "message-1"),
				timestamp: 0
			)
		])

		#expect(throws: AppStateChatMessageRangeError.missingTimestamp) {
			try range.proto()
		}
	}
}
