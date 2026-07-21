import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward poll update messages")
struct WhatsAppClientForwardPollUpdateMessageTests {
	@Test("forwards received poll update and result snapshot messages through the encrypted send path")
	func forwardsReceivedPollUpdateAndResultSnapshotMessagesThroughEncryptedSendPath() async throws {
		let key = ReceivedMessageKey(
			remoteJID: "258840000000@s.whatsapp.net",
			fromMe: false,
			id: "3EB0POLL",
			participant: "258841111111@s.whatsapp.net"
		)
		let updateMessage = try await forwardedMessage(content: .pollUpdate(ReceivedPollUpdateContent(
			pollCreationMessageKey: key,
			encryptedPayload: Data([0x01, 0x02, 0x03]),
			encryptedIV: Data([0x04, 0x05, 0x06]),
			senderTimestampMilliseconds: 1_700_002_000_000
		)))

		#expect(updateMessage.hasPollUpdateMessage)
		#expect(updateMessage.pollUpdateMessage.pollCreationMessageKey.id == "3EB0POLL")
		#expect(updateMessage.pollUpdateMessage.vote.encPayload == Data([0x01, 0x02, 0x03]))
		#expect(updateMessage.pollUpdateMessage.vote.encIv == Data([0x04, 0x05, 0x06]))
		#expect(updateMessage.pollUpdateMessage.senderTimestampMs == 1_700_002_000_000)

		let snapshotMessage = try await forwardedMessage(content: .pollResultSnapshot(ReceivedPollResultSnapshotContent(
			name: "Launch window",
			votes: [ReceivedPollResultVote(optionName: "Morning", voteCount: 7)],
			pollType: .quiz
		)))

		#expect(snapshotMessage.hasPollResultSnapshotMessage)
		#expect(snapshotMessage.pollResultSnapshotMessage.name == "Launch window")
		#expect(snapshotMessage.pollResultSnapshotMessage.pollVotes.map(\.optionName) == ["Morning"])
		#expect(snapshotMessage.pollResultSnapshotMessage.pollVotes.map(\.optionVoteCount) == [7])
		#expect(snapshotMessage.pollResultSnapshotMessage.pollType == .quiz)
	}

	private func forwardedMessage(content: ReceivedMessageContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x2e]))],
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
				id: "POLLUPDATE1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: content,
				fromMe: false
			),
			messageID: "3EB0FORWARDPOLLUPDATE"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
