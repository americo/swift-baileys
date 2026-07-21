import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client poll updates")
struct WhatsAppClientPollUpdateTests {
	@Test("incoming poll update messages emit poll updates before the envelope")
	func incomingPollUpdateMessagesEmitPollUpdatesBeforeTheEnvelope() async throws {
		var key = Proto_MessageKey()
		key.remoteJid = "120363000000000000@g.us"
		key.fromMe = false
		key.id = "POLL_TARGET"
		key.participant = "258840000000@s.whatsapp.net"
		var vote = Proto_Message.PollEncValue()
		vote.encPayload = Data([0x01, 0x02, 0x03])
		vote.encIv = Data([0x04, 0x05, 0x06])
		var update = Proto_Message.PollUpdateMessage()
		update.pollCreationMessageKey = key
		update.vote = vote
		update.senderTimestampMs = 1_700_002_000_000
		var message = Proto_Message()
		message.pollUpdateMessage = update
		let client = WhatsAppClient(messageDecryptor: PollUpdateDecryptor(message: message))
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(pollUpdateNode(id: "poll-update-message"))

		#expect(await events.next() == .messagePollUpdates([
			ReceivedMessagePollUpdate(
				key: WhatsAppMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "POLL_TARGET",
					participant: "258840000000@s.whatsapp.net"
				),
				pollUpdateMessageKey: WhatsAppMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "poll-update-message",
					participant: "456@s.whatsapp.net"
				),
				encryptedPayload: Data([0x01, 0x02, 0x03]),
				encryptedIV: Data([0x04, 0x05, 0x06]),
				senderTimestampMilliseconds: 1_700_002_000_000
			)
		]))
		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "poll-update-message",
			from: "120363000000000000@g.us",
			timestamp: 1_700_000_007,
			content: .pollUpdate(ReceivedPollUpdateContent(
				pollCreationMessageKey: ReceivedMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "POLL_TARGET",
					participant: "258840000000@s.whatsapp.net"
				),
				encryptedPayload: Data([0x01, 0x02, 0x03]),
				encryptedIV: Data([0x04, 0x05, 0x06]),
				senderTimestampMilliseconds: 1_700_002_000_000
			)),
			participant: "456@s.whatsapp.net"
		)))
	}

	@Test("incoming poll updates include decrypted option hashes when context is available")
	func incomingPollUpdatesIncludeDecryptedOptionHashesWhenContextIsAvailable() async throws {
		var key = Proto_MessageKey()
		key.remoteJid = "120363000000000000@g.us"
		key.fromMe = false
		key.id = "3EB0POLLCREATE"
		key.participant = "111@s.whatsapp.net"
		var vote = Proto_Message.PollEncValue()
		vote.encPayload = Data([
			0x8d, 0x00, 0x3b, 0xd1, 0x29, 0x2a, 0xa2, 0xd6, 0x0d, 0xaa, 0xce, 0x61, 0xc4,
			0x71, 0xb4, 0xa1, 0xcb, 0xca, 0xec, 0x66, 0x0f, 0x18, 0xc1, 0x8f, 0xb9
		])
		vote.encIv = Data([0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b])
		var update = Proto_Message.PollUpdateMessage()
		update.pollCreationMessageKey = key
		update.vote = vote
		update.senderTimestampMs = 1_700_002_000_000
		var message = Proto_Message()
		message.pollUpdateMessage = update
		let client = WhatsAppClient(messageDecryptor: PollUpdateDecryptor(message: message))
		await client.configurePollVoteContextResolver(PollVoteContextResolver(context: PollVoteDecryptionContext(
			pollMessageID: "3EB0POLLCREATE",
			pollCreatorJID: "111@s.whatsapp.net",
			voterJID: "222@s.whatsapp.net",
			pollEncKey: Data(0x00...0x1f)
		)))
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(pollUpdateNode(id: "poll-update-message", participant: "222@s.whatsapp.net"))

		#expect(await events.next() == .messagePollUpdates([
			ReceivedMessagePollUpdate(
				key: WhatsAppMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "3EB0POLLCREATE",
					participant: "111@s.whatsapp.net"
				),
				pollUpdateMessageKey: WhatsAppMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "poll-update-message",
					participant: "222@s.whatsapp.net"
				),
				encryptedPayload: vote.encPayload,
				encryptedIV: vote.encIv,
				senderTimestampMilliseconds: 1_700_002_000_000,
				selectedOptionHashes: [Data([0x01, 0x02, 0x03]), Data([0xaa, 0xbb])]
			)
		]))
	}
}

private struct PollUpdateDecryptor: IncomingMessageDecrypting {
	let message: Proto_Message

	func decryptIncomingMessage(from node: BinaryNode) async throws -> Proto_Message? {
		message
	}
}

private struct PollVoteContextResolver: PollVoteContextResolving {
	let context: PollVoteDecryptionContext

	func context(
		for key: WhatsAppMessageKey,
		pollUpdateMessageKey: WhatsAppMessageKey
	) async throws -> PollVoteDecryptionContext? {
		context
	}
}

private func pollUpdateNode(id: String, participant: String = "456@s.whatsapp.net") -> BinaryNode {
	BinaryNode(
		tag: "message",
		attrs: [
			"id": id,
			"from": "120363000000000000@g.us",
			"participant": participant,
			"t": "1700000007"
		],
		content: .nodes([
			BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0xaa, 0xbb])))
		])
	)
}
