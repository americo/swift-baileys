import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client live location messages")
struct WhatsAppClientLiveLocationMessageTests {
	@Test("sends live location messages after resolving recipient devices")
	func sendsLiveLocationMessagesAfterResolvingRecipientDevices() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0x41]))
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

		let messageID = try await client.sendLiveLocationMessage(
			to: "123@s.whatsapp.net",
			location: OutgoingLiveLocationContent(
				latitude: -25.966213,
				longitude: 32.56745,
				accuracyInMeters: 12,
				speedInMetersPerSecond: 1.5,
				degreesClockwiseFromMagneticNorth: 90,
				caption: "On my way",
				sequenceNumber: 7,
				timeOffsetSeconds: 30,
				jpegThumbnail: Data([0x03, 0x04])
			),
			messageID: "3EB0LIVELOCATION"
		)

		#expect(messageID == "3EB0LIVELOCATION")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		let calls = await encryptor.calls
		let protobufMessage = try Proto_Message(serializedBytes: calls[0].data.dropLast())
		#expect(protobufMessage.liveLocationMessage.degreesLatitude == -25.966213)
		#expect(protobufMessage.liveLocationMessage.degreesLongitude == 32.56745)
		#expect(protobufMessage.liveLocationMessage.accuracyInMeters == 12)
		#expect(protobufMessage.liveLocationMessage.speedInMps == 1.5)
		#expect(protobufMessage.liveLocationMessage.degreesClockwiseFromMagneticNorth == 90)
		#expect(protobufMessage.liveLocationMessage.caption == "On my way")
		#expect(protobufMessage.liveLocationMessage.sequenceNumber == 7)
		#expect(protobufMessage.liveLocationMessage.timeOffset == 30)
		#expect(protobufMessage.liveLocationMessage.jpegThumbnail == Data([0x03, 0x04]))

		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0LIVELOCATION")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
	}
}
