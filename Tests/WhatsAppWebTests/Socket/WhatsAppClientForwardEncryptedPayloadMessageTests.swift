import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward encrypted payload messages")
struct WhatsAppClientForwardEncryptedPayloadMessageTests {
	@Test("forwards received encrypted comment and secret encrypted messages through the encrypted send path")
	func forwardsReceivedEncryptedCommentAndSecretEncryptedMessagesThroughEncryptedSendPath() async throws {
		let key = ReceivedMessageKey(
			remoteJID: "status@broadcast",
			fromMe: false,
			id: "target-status",
			participant: nil
		)
		let commentMessage = try await forwardedMessage(content: .encryptedComment(ReceivedEncryptedCommentContent(
			targetMessageKey: key,
			encryptedPayload: Data([0x01, 0x02]),
			encryptedIV: Data([0x03, 0x04])
		)))

		#expect(commentMessage.hasEncCommentMessage)
		#expect(commentMessage.encCommentMessage.targetMessageKey.id == "target-status")
		#expect(commentMessage.encCommentMessage.encPayload == Data([0x01, 0x02]))
		#expect(commentMessage.encCommentMessage.encIv == Data([0x03, 0x04]))

		let reactionMessage = try await forwardedMessage(content: .encryptedReaction(ReceivedEncryptedReactionContent(
			targetMessageKey: key,
			encryptedPayload: Data([0x09, 0x0a]),
			encryptedIV: Data([0x0b, 0x0c])
		)))

		#expect(reactionMessage.hasEncReactionMessage)
		#expect(reactionMessage.encReactionMessage.targetMessageKey.remoteJid == "status@broadcast")
		#expect(reactionMessage.encReactionMessage.encPayload == Data([0x09, 0x0a]))
		#expect(reactionMessage.encReactionMessage.encIv == Data([0x0b, 0x0c]))

		let secretMessage = try await forwardedMessage(content: .secretEncrypted(ReceivedSecretEncryptedContent(
			targetMessageKey: key,
			encryptedPayload: Data([0x05, 0x06]),
			encryptedIV: Data([0x07, 0x08]),
			type: .messageEdit
		)))

		#expect(secretMessage.hasSecretEncryptedMessage)
		#expect(secretMessage.secretEncryptedMessage.targetMessageKey.remoteJid == "status@broadcast")
		#expect(secretMessage.secretEncryptedMessage.encPayload == Data([0x05, 0x06]))
		#expect(secretMessage.secretEncryptedMessage.encIv == Data([0x07, 0x08]))
		#expect(secretMessage.secretEncryptedMessage.secretEncType == .messageEdit)
	}

	private func forwardedMessage(content: ReceivedMessageContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x2c]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "ENCRYPTED1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDENCRYPTED"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
