import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client member label send")
struct WhatsAppClientMemberLabelSendTests {
	@Test("Baileys updateMemberLabel alias sends group member label protocol messages")
	func baileysUpdateMemberLabelAliasSendsGroupMemberLabelProtocolMessages() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0xaa]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123:0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		let messageID = try await client.updateMemberLabel(
			"123@s.whatsapp.net",
			memberLabel: "abcdefghijklmnopqrstuvwxyz0123456789",
			timestamp: 1_700_000_000,
			messageID: "3EB0MEMBERLABEL"
		)

		#expect(messageID == "3EB0MEMBERLABEL")
		let calls = await encryptor.calls
		let message = try Proto_Message(serializedBytes: calls[0].data.dropLast())
		#expect(message.protocolMessage.type == .groupMemberLabelChange)
		#expect(message.protocolMessage.memberLabel.label == "abcdefghijklmnopqrstuvwxyz0123")
		#expect(message.protocolMessage.memberLabel.labelTimestamp == 1_700_000_000)

		let stanza = try await sentMessageNode(from: transport, at: 0)
		#expect(stanza.attrs["id"] == "3EB0MEMBERLABEL")
		#expect(stanza.firstChild(named: "meta")?.attrs["tag_reason"] == "user_update")
		#expect(stanza.firstChild(named: "meta")?.attrs["appdata"] == "member_tag")
	}

	private func sentMessageNode(from transport: MockMessageSendWebSocketTransport, at index: Int) async throws -> BinaryNode {
		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[index])
		return try BinaryNodeDecoder().decode(frames[0])
	}
}
