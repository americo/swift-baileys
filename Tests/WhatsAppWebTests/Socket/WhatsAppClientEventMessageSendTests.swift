import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client event message send")
struct WhatsAppClientEventMessageSendTests {
	@Test("sends event messages after resolving recipient devices")
	func sendsEventMessagesAfterResolvingRecipientDevices() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0xaa]))
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

		let event = OutgoingEventContent(
			name: "Swift meetup",
			description: "Discuss Baileys porting",
			startTime: 1_800_000_000,
			endTime: 1_800_003_600,
			joinLink: "https://call.whatsapp.com/swift"
		)
		let messageID = try await client.sendEventMessage(
			to: "123@s.whatsapp.net",
			event: event,
			messageID: "3EB0EVENT"
		)

		#expect(messageID == "3EB0EVENT")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		#expect(await callOrder.values == ["sessions", "encrypt:123.0@s.whatsapp.net"])
		let encryptorCalls = await encryptor.calls
		let protobufMessage = try Proto_Message(serializedBytes: encryptorCalls[0].data.dropLast())
		#expect(protobufMessage.eventMessage.name == event.name)
		#expect(protobufMessage.eventMessage.description_p == event.description)
		#expect(protobufMessage.eventMessage.startTime == event.startTime)
		#expect(protobufMessage.eventMessage.endTime == event.endTime)

		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0EVENT")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
	}

	@Test("sends encrypted event response messages after resolving recipient devices")
	func sendsEncryptedEventResponseMessagesAfterResolvingRecipientDevices() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0xbb]))
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

		let target = EventCreationMessageTarget(
			chatJID: "123@s.whatsapp.net",
			messageID: "3EB0EVENTCREATE",
			fromMe: false
		)
		let response = OutgoingEventResponseContent(
			response: .going,
			timestampMilliseconds: 1_800_000_123_456,
			extraGuestCount: 2
		)
		let messageID = try await client.sendEventResponseMessage(
			to: "123@s.whatsapp.net",
			target: target,
			response: response,
			eventCreatorJID: "111@s.whatsapp.net",
			responderJID: "222@s.whatsapp.net",
			eventMessageSecret: try hexData("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"),
			messageID: "3EB0EVENTRESPONSE",
			eventResponseCipher: EventResponseCipher(ivGenerator: {
				try hexData("202122232425262728292a2b")
			})
		)

		#expect(messageID == "3EB0EVENTRESPONSE")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		#expect(await callOrder.values == ["sessions", "encrypt:123.0@s.whatsapp.net"])
		let encryptorCalls = await encryptor.calls
		let protobufMessage = try Proto_Message(serializedBytes: encryptorCalls[0].data.dropLast())
		let encryptedResponse = protobufMessage.encEventResponseMessage
		#expect(encryptedResponse.eventCreationMessageKey.remoteJid == target.chatJID)
		#expect(encryptedResponse.eventCreationMessageKey.id == target.messageID)
		#expect(encryptedResponse.eventCreationMessageKey.fromMe == target.fromMe)
		#expect(encryptedResponse.encIv == (try hexData("202122232425262728292a2b")))
		#expect(encryptedResponse.encPayload == (try hexData("e5e06ccecdde6bc10ab15672664cd3251c67a7a96bb87b79ee34ea")))

		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0EVENTRESPONSE")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
	}
}
