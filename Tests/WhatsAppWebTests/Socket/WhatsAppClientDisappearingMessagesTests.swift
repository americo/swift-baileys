import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client disappearing messages")
struct WhatsAppClientDisappearingMessagesTests {
	@Test("sends disappearing message settings after resolving recipient devices")
	func sendsDisappearingMessageSettingsAfterResolvingRecipientDevices() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0xfe]))
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

		let messageID = try await client.sendDisappearingMessagesSetting(
			to: "123@s.whatsapp.net",
			content: OutgoingDisappearingMessagesContent(expirationSeconds: 86_400),
			messageID: "3EB0DISAPPEARING"
		)

		#expect(messageID == "3EB0DISAPPEARING")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		let calls = await encryptor.calls
		let protobufMessage = try Proto_Message(serializedBytes: calls[0].data.dropLast())
		#expect(protobufMessage.ephemeralMessage.message.protocolMessage.type == .ephemeralSetting)
		#expect(protobufMessage.ephemeralMessage.message.protocolMessage.ephemeralExpiration == 86_400)

		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0DISAPPEARING")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
	}
}
