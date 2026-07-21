import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client album messages")
struct WhatsAppClientAlbumMessageTests {
	@Test("sends album messages after resolving recipient devices")
	func sendsAlbumMessagesAfterResolvingRecipientDevices() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0xee]))
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

		let messageID = try await client.sendAlbumMessage(
			to: "123@s.whatsapp.net",
			album: OutgoingAlbumContent(expectedImageCount: 2, expectedVideoCount: 1),
			messageID: "3EB0ALBUM"
		)

		#expect(messageID == "3EB0ALBUM")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		#expect(await callOrder.values == ["sessions", "encrypt:123.0@s.whatsapp.net"])
		let encryptorCalls = await encryptor.calls
		let protobufMessage = try Proto_Message(serializedBytes: encryptorCalls[0].data.dropLast())
		#expect(protobufMessage.albumMessage.expectedImageCount == 2)
		#expect(protobufMessage.albumMessage.expectedVideoCount == 1)

		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0ALBUM")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
	}
}
