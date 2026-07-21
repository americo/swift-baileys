import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client message actions")
struct WhatsAppClientMessageActionTests {
	@Test("revokes own messages with edit 7 protocol message")
	func revokesOwnMessagesWithEdit7ProtocolMessage() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0x21]))
		], callOrder: callOrder)
		let deviceResolver = StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"])
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: sessionPreparer,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		let messageID = try await client.sendDeleteMessage(
			target: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: true,
				id: "3EB0TARGETDELETE"
			),
			messageID: "3EB0DELETE"
		)

		#expect(messageID == "3EB0DELETE")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		let stanza = try await sentMessageStanza(from: transport)
		#expect(stanza.attrs["id"] == "3EB0DELETE")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
		#expect(stanza.attrs["edit"] == "7")

		let protobufMessage = try await encryptedProtoMessage(from: encryptor)
		#expect(protobufMessage.protocolMessage.type == .revoke)
		#expect(protobufMessage.protocolMessage.key.remoteJid == "123@s.whatsapp.net")
		#expect(protobufMessage.protocolMessage.key.fromMe)
		#expect(protobufMessage.protocolMessage.key.id == "3EB0TARGETDELETE")
	}

	@Test("revokes group messages as admin with edit 8")
	func revokesGroupMessagesAsAdminWithEdit8() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0x22]))
		], callOrder: callOrder)
		let deviceResolver = StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"])
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: sessionPreparer,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendDeleteMessage(
			target: WhatsAppMessageKey(
				remoteJID: "120363000000000000@g.us",
				fromMe: false,
				id: "3EB0GROUPTARGET",
				participant: "456@s.whatsapp.net"
			),
			messageID: "3EB0GROUPDELETE"
		)

		let stanza = try await sentMessageStanza(from: transport)
		#expect(stanza.attrs["to"] == "120363000000000000@g.us")
		#expect(stanza.attrs["edit"] == "8")
		let protobufMessage = try await encryptedProtoMessage(from: encryptor)
		#expect(protobufMessage.protocolMessage.key.participant == "456@s.whatsapp.net")
	}

	@Test("edits text messages with edit 1 protocol message")
	func editsTextMessagesWithEdit1ProtocolMessage() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0x23]))
		], callOrder: callOrder)
		let deviceResolver = StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"])
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: sessionPreparer,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendEditMessage(
			target: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: true,
				id: "3EB0TARGETEDIT"
			),
			text: "edited from swift",
			mentions: ["111@s.whatsapp.net"],
			mentionAll: true,
			isForwarded: true,
			forwardingScore: 4,
			timestampMilliseconds: 1_700_001_000_000,
			messageID: "3EB0EDIT"
		)

		let stanza = try await sentMessageStanza(from: transport)
		#expect(stanza.attrs["id"] == "3EB0EDIT")
		#expect(stanza.attrs["edit"] == "1")
		let protobufMessage = try await encryptedProtoMessage(from: encryptor)
		#expect(protobufMessage.protocolMessage.type == .messageEdit)
		#expect(protobufMessage.protocolMessage.key.id == "3EB0TARGETEDIT")
		#expect(protobufMessage.protocolMessage.timestampMs == 1_700_001_000_000)
		#expect(protobufMessage.protocolMessage.editedMessage.extendedTextMessage.text == "edited from swift")
		#expect(protobufMessage.protocolMessage.editedMessage.extendedTextMessage.contextInfo.mentionedJid == ["111@s.whatsapp.net"])
		#expect(protobufMessage.protocolMessage.editedMessage.extendedTextMessage.contextInfo.nonJidMentions == 1)
		#expect(protobufMessage.protocolMessage.editedMessage.extendedTextMessage.contextInfo.isForwarded == true)
		#expect(protobufMessage.protocolMessage.editedMessage.extendedTextMessage.contextInfo.forwardingScore == 4)
	}

	@Test("pins messages with edit 2 pin in chat message")
	func pinsMessagesWithEdit2PinInChatMessage() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0x24]))
		], callOrder: callOrder)
		let deviceResolver = StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"])
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: sessionPreparer,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendPinMessage(
			target: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: false,
				id: "3EB0TARGETPIN"
			),
			action: .pin,
			duration: 604_800,
			timestampMilliseconds: 1_700_002_000_000,
			messageID: "3EB0PIN"
		)

		let stanza = try await sentMessageStanza(from: transport)
		#expect(stanza.attrs["id"] == "3EB0PIN")
		#expect(stanza.attrs["edit"] == "2")
		let protobufMessage = try await encryptedProtoMessage(from: encryptor)
		#expect(protobufMessage.pinInChatMessage.key.id == "3EB0TARGETPIN")
		#expect(protobufMessage.pinInChatMessage.type == .pinForAll)
		#expect(protobufMessage.pinInChatMessage.senderTimestampMs == 1_700_002_000_000)
		#expect(protobufMessage.messageContextInfo.messageAddOnDurationInSecs == 604_800)
	}

	@Test("unpins messages with zero duration")
	func unpinsMessagesWithZeroDuration() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0x25]))
		], callOrder: callOrder)
		let deviceResolver = StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"])
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: sessionPreparer,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendPinMessage(
			target: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: false,
				id: "3EB0TARGETUNPIN"
			),
			action: .unpin,
			messageID: "3EB0UNPIN"
		)

		let stanza = try await sentMessageStanza(from: transport)
		#expect(stanza.attrs["edit"] == "2")
		let protobufMessage = try await encryptedProtoMessage(from: encryptor)
		#expect(protobufMessage.pinInChatMessage.type == .unpinForAll)
		#expect(protobufMessage.messageContextInfo.messageAddOnDurationInSecs == 0)
	}
}

private func sentMessageStanza(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	var codec = NoiseFrameCodec()
	let frames = codec.decode(await transport.sentFrames[0])
	return try BinaryNodeDecoder().decode(frames[0])
}

private func encryptedProtoMessage(from encryptor: StubMessageSendEncryptor) async throws -> Proto_Message {
	let calls = await encryptor.calls
	return try Proto_Message(serializedBytes: calls[0].data.dropLast())
}
