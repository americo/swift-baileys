import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client interactive reply messages")
struct WhatsAppClientInteractiveReplyMessageTests {
	@Test("sends plain button reply messages after resolving recipient devices")
	func sendsPlainButtonReplyMessagesAfterResolvingRecipientDevices() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0xfb]))
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

		let messageID = try await client.sendButtonReplyMessage(
			to: "123@s.whatsapp.net",
			content: OutgoingButtonReplyContent(
				style: .plain,
				id: "confirm",
				displayText: "Confirm",
				index: 0
			),
			messageID: "3EB0BUTTONREPLY"
		)

		#expect(messageID == "3EB0BUTTONREPLY")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		let calls = await encryptor.calls
		let protobufMessage = try Proto_Message(serializedBytes: calls[0].data.dropLast())
		#expect(protobufMessage.buttonsResponseMessage.selectedButtonID == "confirm")
		#expect(protobufMessage.buttonsResponseMessage.selectedDisplayText == "Confirm")
		#expect(protobufMessage.buttonsResponseMessage.type == .displayText)

		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0BUTTONREPLY")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
	}

	@Test("sends template button reply messages after resolving recipient devices")
	func sendsTemplateButtonReplyMessagesAfterResolvingRecipientDevices() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0xfd]))
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

		let messageID = try await client.sendButtonReplyMessage(
			to: "123@s.whatsapp.net",
			content: OutgoingButtonReplyContent(
				style: .template,
				id: "ship_now",
				displayText: "Ship now",
				index: 2
			),
			messageID: "3EB0TEMPLATEBUTTONREPLY"
		)

		#expect(messageID == "3EB0TEMPLATEBUTTONREPLY")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		let calls = await encryptor.calls
		let protobufMessage = try Proto_Message(serializedBytes: calls[0].data.dropLast())
		#expect(protobufMessage.templateButtonReplyMessage.selectedID == "ship_now")
		#expect(protobufMessage.templateButtonReplyMessage.selectedDisplayText == "Ship now")
		#expect(protobufMessage.templateButtonReplyMessage.selectedIndex == 2)

		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0TEMPLATEBUTTONREPLY")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
	}

	@Test("sends list reply messages after resolving recipient devices")
	func sendsListReplyMessagesAfterResolvingRecipientDevices() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0xfc]))
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

		let messageID = try await client.sendListReplyMessage(
			to: "123@s.whatsapp.net",
			content: OutgoingListReplyContent(
				title: "Delivery",
				selectedRowID: "delivery",
				description: "Send it to my address"
			),
			messageID: "3EB0LISTREPLY"
		)

		#expect(messageID == "3EB0LISTREPLY")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		let calls = await encryptor.calls
		let protobufMessage = try Proto_Message(serializedBytes: calls[0].data.dropLast())
		#expect(protobufMessage.listResponseMessage.title == "Delivery")
		#expect(protobufMessage.listResponseMessage.listType == .singleSelect)
		#expect(protobufMessage.listResponseMessage.singleSelectReply.selectedRowID == "delivery")
		#expect(protobufMessage.listResponseMessage.description_p == "Send it to my address")

		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0LISTREPLY")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
	}
}
