import Testing
@testable import WhatsAppWeb

@Suite("Message forward protocol action content builder")
struct MessageForwardProtocolActionContentBuilderTests {
	@Test("forwards revoked protocol messages as pass-through content")
	func forwardsRevokedProtocolMessagesAsPassThroughContent() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "258840000000@s.whatsapp.net"
		key.fromMe = true
		key.id = "3EB0REVOKED"
		var action = Proto_Message.ProtocolMessageMessage()
		action.type = .revoke
		action.key = key
		action.timestampMs = 1_700_001_000_000
		var source = Proto_Message()
		source.protocolMessage = action

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasProtocolMessage)
		#expect(message.protocolMessage.type == .revoke)
		#expect(message.protocolMessage.key.id == "3EB0REVOKED")
		#expect(message.protocolMessage.timestampMs == 1_700_001_000_000)
	}

	@Test("forwards edited protocol messages by forwarding nested edited content")
	func forwardsEditedProtocolMessagesByForwardingNestedEditedContent() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "258840000000@s.whatsapp.net"
		key.fromMe = false
		key.id = "3EB0EDITED"
		var action = Proto_Message.ProtocolMessageMessage()
		action.type = .messageEdit
		action.key = key
		action.editedMessage = MessageContentBuilder.text("edited text")
		action.timestampMs = 1_700_001_111_000
		var source = Proto_Message()
		source.protocolMessage = action

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasProtocolMessage)
		#expect(message.protocolMessage.type == .messageEdit)
		#expect(message.protocolMessage.key.id == "3EB0EDITED")
		#expect(message.protocolMessage.timestampMs == 1_700_001_111_000)
		#expect(message.protocolMessage.editedMessage.extendedTextMessage.text == "edited text")
		#expect(message.protocolMessage.editedMessage.extendedTextMessage.contextInfo.isForwarded)
	}
}
