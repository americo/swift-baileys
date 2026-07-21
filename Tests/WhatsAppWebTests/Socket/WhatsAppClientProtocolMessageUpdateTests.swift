import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client protocol message updates")
struct WhatsAppClientProtocolMessageUpdateTests {
	@Test("revoke protocol messages emit message updates before the envelope")
	func revokeProtocolMessagesEmitMessageUpdatesBeforeTheEnvelope() async throws {
		var revokedKey = Proto_MessageKey()
		revokedKey.remoteJid = "123@s.whatsapp.net"
		revokedKey.id = "target-message"
		revokedKey.fromMe = false
		revokedKey.participant = "456@s.whatsapp.net"
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .revoke
		protocolMessage.key = revokedKey
		protocolMessage.timestampMs = 1_700_000_004_000
		let client = WhatsAppClient(messageDecryptor: ProtocolMessageUpdateDecryptor(
			message: protocolMessageMessage(protocolMessage)
		))
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(protocolMessageUpdateNode(id: "revoke-envelope"))

		#expect(await events.next() == .messagesUpdated([
			ReceivedMessageUpdate(
				key: WhatsAppMessageKey(
					remoteJID: "123@s.whatsapp.net",
					fromMe: false,
					id: "target-message",
					participant: "456@s.whatsapp.net"
				),
				status: nil,
				timestamp: 1_700_000_004,
				stub: ReceivedMessageStubContent(type: .revoke, parameters: []),
				protocolMessageKey: WhatsAppMessageKey(
					remoteJID: "123@s.whatsapp.net",
					fromMe: false,
					id: "revoke-envelope",
					participant: "456@s.whatsapp.net"
				),
				protocolAction: .revoke
			)
		]))
		guard case .receivedMessage(let envelope)? = await events.next() else {
			Issue.record("Expected revoke envelope after message update")
			return
		}
		#expect(envelope.content == .messageRevoked(ReceivedMessageRevokedContent(
			key: ReceivedMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: false,
				id: "target-message",
				participant: "456@s.whatsapp.net"
			),
			timestampMilliseconds: 1_700_000_004_000
		)))
	}

	@Test("edit protocol messages emit edited content updates")
	func editProtocolMessagesEmitEditedContentUpdates() async throws {
		var editedKey = Proto_MessageKey()
		editedKey.remoteJid = "123@s.whatsapp.net"
		editedKey.id = "target-message"
		editedKey.fromMe = true
		var editedMessage = Proto_Message()
		editedMessage.conversation = "edited text"
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .messageEdit
		protocolMessage.key = editedKey
		protocolMessage.editedMessage = editedMessage
		protocolMessage.timestampMs = 1_700_000_005_000
		let client = WhatsAppClient(messageDecryptor: ProtocolMessageUpdateDecryptor(
			message: protocolMessageMessage(protocolMessage)
		))
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(protocolMessageUpdateNode(id: "edit-envelope", participant: nil))

		#expect(await events.next() == .messagesUpdated([
			ReceivedMessageUpdate(
				key: WhatsAppMessageKey(
					remoteJID: "123@s.whatsapp.net",
					fromMe: true,
					id: "target-message"
				),
				status: nil,
				timestamp: 1_700_000_005,
				content: .text("edited text"),
				protocolMessageKey: WhatsAppMessageKey(
					remoteJID: "123@s.whatsapp.net",
					fromMe: false,
					id: "edit-envelope"
				),
				protocolAction: .edit
			)
		]))
	}

	@Test("ephemeral setting protocol messages emit update content")
	func ephemeralSettingProtocolMessagesEmitUpdateContent() async throws {
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .ephemeralSetting
		protocolMessage.ephemeralExpiration = 86_400
		protocolMessage.ephemeralSettingTimestamp = 1_700_000_006
		let client = WhatsAppClient(messageDecryptor: ProtocolMessageUpdateDecryptor(
			message: protocolMessageMessage(protocolMessage)
		))
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(protocolMessageUpdateNode(id: "ephemeral-envelope", participant: nil))

		#expect(await events.next() == .messagesUpdated([
			ReceivedMessageUpdate(
				key: WhatsAppMessageKey(
					remoteJID: "123@s.whatsapp.net",
					fromMe: false,
					id: "ephemeral-envelope"
				),
				status: nil,
				timestamp: 1_700_000_006,
				content: .ephemeralSetting(ReceivedEphemeralSettingContent(
					expirationSeconds: 86_400,
					settingTimestampSeconds: 1_700_000_006,
					disappearingMode: nil
				)),
				protocolMessageKey: WhatsAppMessageKey(
					remoteJID: "123@s.whatsapp.net",
					fromMe: false,
					id: "ephemeral-envelope"
				),
				protocolAction: .ephemeralSetting
			)
		]))
	}
}

private struct ProtocolMessageUpdateDecryptor: IncomingMessageDecrypting {
	let message: Proto_Message

	func decryptIncomingMessage(from node: BinaryNode) async throws -> Proto_Message? {
		message
	}
}

private func protocolMessageMessage(_ protocolMessage: Proto_Message.ProtocolMessageMessage) -> Proto_Message {
	var message = Proto_Message()
	message.protocolMessage = protocolMessage
	return message
}

private func protocolMessageUpdateNode(id: String, participant: String? = "456@s.whatsapp.net") -> BinaryNode {
	var attrs = [
		("id", id),
		("from", "123@s.whatsapp.net"),
		("t", "1700000007")
	]
	if let participant {
		attrs.append(("participant", participant))
	}
	return BinaryNode(
		tag: "message",
		attrs: BinaryNode.Attributes(attrs),
		content: .nodes([
			BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0xaa, 0xbb])))
		])
	)
}
