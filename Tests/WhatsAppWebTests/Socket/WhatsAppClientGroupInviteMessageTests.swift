import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client group invite messages")
struct WhatsAppClientGroupInviteMessageTests {
	@Test("sends group invite messages after resolving recipient devices")
	func sendsGroupInviteMessagesAfterResolvingRecipientDevices() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0x31]))
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

		let messageID = try await client.sendGroupInviteMessage(
			to: "123@s.whatsapp.net",
			invite: OutgoingGroupInviteContent(
				groupJID: "120363000000000000@g.us",
				inviteCode: "ABCD1234",
				inviteExpiration: 1_700_010_000,
				groupName: "Swift Group",
				caption: "Join us",
				jpegThumbnail: Data([0x01, 0x02])
			),
			messageID: "3EB0GROUPINVITE"
		)

		#expect(messageID == "3EB0GROUPINVITE")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		let calls = await encryptor.calls
		let protobufMessage = try Proto_Message(serializedBytes: calls[0].data.dropLast())
		#expect(protobufMessage.groupInviteMessage.groupJid == "120363000000000000@g.us")
		#expect(protobufMessage.groupInviteMessage.inviteCode == "ABCD1234")
		#expect(protobufMessage.groupInviteMessage.inviteExpiration == 1_700_010_000)
		#expect(protobufMessage.groupInviteMessage.groupName == "Swift Group")
		#expect(protobufMessage.groupInviteMessage.caption == "Join us")
		#expect(protobufMessage.groupInviteMessage.jpegThumbnail == Data([0x01, 0x02]))

		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0GROUPINVITE")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
	}
}
