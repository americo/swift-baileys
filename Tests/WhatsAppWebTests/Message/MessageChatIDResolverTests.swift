import Testing
@testable import WhatsAppWeb

@Suite("Message chat id resolver")
struct MessageChatIDResolverTests {
	@Test("returns remote jid for normal chats")
	func returnsRemoteJIDForNormalChats() throws {
		let key = WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "message-id")

		#expect(try MessageChatIDResolver.chatID(for: key) == "123@s.whatsapp.net")
	}

	@Test("returns participant for incoming non-status broadcasts")
	func returnsParticipantForIncomingNonStatusBroadcasts() throws {
		let key = WhatsAppMessageKey(
			remoteJID: "newsletter@broadcast",
			fromMe: false,
			id: "message-id",
			participant: "456@s.whatsapp.net"
		)

		#expect(try MessageChatIDResolver.chatID(for: key) == "456@s.whatsapp.net")
	}

	@Test("keeps remote jid for outgoing and status broadcasts")
	func keepsRemoteJIDForOutgoingAndStatusBroadcasts() throws {
		#expect(try MessageChatIDResolver.chatID(for: WhatsAppMessageKey(
			remoteJID: "newsletter@broadcast",
			fromMe: true,
			id: "outgoing-id",
			participant: "456@s.whatsapp.net"
		)) == "newsletter@broadcast")
		#expect(try MessageChatIDResolver.chatID(for: WhatsAppMessageKey(
			remoteJID: "status@broadcast",
			fromMe: false,
			id: "status-id",
			participant: "456@s.whatsapp.net"
		)) == "status@broadcast")
	}

	@Test("throws typed errors for incomplete keys")
	func throwsTypedErrorsForIncompleteKeys() {
		#expect(throws: MessageChatIDResolutionError.missingRemoteJID) {
			try MessageChatIDResolver.chatID(for: WhatsAppMessageKey(remoteJID: nil, fromMe: false, id: "message-id"))
		}
		#expect(throws: MessageChatIDResolutionError.missingBroadcastParticipant(
			remoteJID: "newsletter@broadcast",
			fromMe: false
		)) {
			try MessageChatIDResolver.chatID(for: WhatsAppMessageKey(
				remoteJID: "newsletter@broadcast",
				fromMe: false,
				id: "message-id"
			))
		}
	}
}
