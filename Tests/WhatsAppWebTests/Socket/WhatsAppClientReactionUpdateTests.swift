import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client reaction updates")
struct WhatsAppClientReactionUpdateTests {
	@Test("incoming reaction messages emit reaction updates before the envelope")
	func incomingReactionMessagesEmitReactionUpdatesBeforeTheEnvelope() async throws {
		var targetKey = Proto_MessageKey()
		targetKey.remoteJid = "123@s.whatsapp.net"
		targetKey.fromMe = false
		targetKey.id = "target-message"
		targetKey.participant = "456@s.whatsapp.net"
		var reaction = Proto_Message.ReactionMessage()
		reaction.key = targetKey
		reaction.text = "+1"
		reaction.groupingKey = "target-message"
		reaction.senderTimestampMs = 1_700_000_999_000
		var message = Proto_Message()
		message.reactionMessage = reaction
		let client = WhatsAppClient(messageDecryptor: ReactionUpdateDecryptor(message: message))
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(reactionUpdateNode(id: "reaction-message"))

		#expect(await events.next() == .messageReactionsUpdated([
			ReceivedMessageReactionUpdate(
				key: WhatsAppMessageKey(
					remoteJID: "123@s.whatsapp.net",
					fromMe: false,
					id: "target-message",
					participant: "456@s.whatsapp.net"
				),
				reactionMessageKey: WhatsAppMessageKey(
					remoteJID: "123@s.whatsapp.net",
					fromMe: false,
					id: "reaction-message",
					participant: "456@s.whatsapp.net"
				),
				text: "+1",
				groupingKey: "target-message",
				senderTimestampMilliseconds: 1_700_000_999_000
			)
		]))
		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "reaction-message",
			from: "123@s.whatsapp.net",
			timestamp: 1_700_000_007,
			content: .reaction(ReceivedReactionContent(
				key: ReceivedMessageKey(
					remoteJID: "123@s.whatsapp.net",
					fromMe: false,
					id: "target-message",
					participant: "456@s.whatsapp.net"
				),
				text: "+1",
				groupingKey: "target-message",
				senderTimestampMilliseconds: 1_700_000_999_000
			)),
			participant: "456@s.whatsapp.net"
		)))
	}

	@Test("incoming reaction events use cleaned target keys from the local perspective")
	func incomingReactionEventsUseCleanedTargetKeysFromTheLocalPerspective() async throws {
		var targetKey = Proto_MessageKey()
		targetKey.remoteJid = "120363000000000000@g.us"
		targetKey.fromMe = false
		targetKey.id = "target-message"
		targetKey.participant = "999@s.whatsapp.net"
		var reaction = Proto_Message.ReactionMessage()
		reaction.key = targetKey
		reaction.text = "+1"
		var message = Proto_Message()
		message.reactionMessage = reaction
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: reactionUpdateCredentials(), keys: InMemorySignalKeyStore()),
			messageDecryptor: ReactionUpdateDecryptor(message: message)
		)
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(groupReactionUpdateNode(id: "reaction-message"))

		#expect(await events.next() == .messageReactionsUpdated([
			ReceivedMessageReactionUpdate(
				key: WhatsAppMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: true,
					id: "target-message",
					participant: "999@s.whatsapp.net"
				),
				reactionMessageKey: WhatsAppMessageKey(
					remoteJID: "120363000000000000@g.us",
					fromMe: false,
					id: "reaction-message",
					participant: "111@s.whatsapp.net"
				),
				text: "+1",
				groupingKey: nil,
				senderTimestampMilliseconds: nil
			)
		]))
		guard case .receivedMessage(let envelope)? = await events.next(),
			  case .reaction(let cleanedReaction) = envelope.content else {
			Issue.record("expected cleaned reaction envelope")
			return
		}

		#expect(envelope.from == "120363000000000000@g.us")
		#expect(envelope.participant == "111@s.whatsapp.net")
		#expect(cleanedReaction.key == ReceivedMessageKey(
			remoteJID: "120363000000000000@g.us",
			fromMe: true,
			id: "target-message",
			participant: "999@s.whatsapp.net"
		))
	}
}

private struct ReactionUpdateDecryptor: IncomingMessageDecrypting {
	let message: Proto_Message

	func decryptIncomingMessage(from node: BinaryNode) async throws -> Proto_Message? {
		message
	}
}

private func reactionUpdateNode(id: String) -> BinaryNode {
	BinaryNode(
		tag: "message",
		attrs: [
			"id": id,
			"from": "123@s.whatsapp.net",
			"participant": "456@s.whatsapp.net",
			"t": "1700000007"
		],
		content: .nodes([
			BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0xaa, 0xbb])))
		])
	)
}

private func groupReactionUpdateNode(id: String) -> BinaryNode {
	BinaryNode(
		tag: "message",
		attrs: [
			"id": id,
			"from": "120363000000000000@g.us",
			"participant": "111@s.whatsapp.net",
			"t": "1700000007"
		],
		content: .nodes([
			BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0xaa, 0xbb])))
		])
	)
}

private func reactionUpdateCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
		signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data([6])),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([8])),
			signature: Data([9]),
			keyID: 1
		),
		registrationID: 559,
		advSecretKey: "adv-secret",
		me: WhatsAppUser(id: "999@s.whatsapp.net", name: "Reaction Bot", lid: "999@lid"),
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true
	)
}
