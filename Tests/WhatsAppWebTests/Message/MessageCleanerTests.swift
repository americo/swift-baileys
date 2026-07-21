import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Message cleaner")
struct MessageCleanerTests {
	@Test("normalizes hosted and device JIDs on the message key")
	func normalizesHostedAndDeviceJIDsOnTheMessageKey() {
		let message = ReceivedMessage(
			id: "message-id",
			from: "123:4@hosted",
			timestamp: nil,
			content: .text("hello"),
			fromMe: false,
			participant: "456:7@hosted.lid"
		)

		let cleaned = MessageCleaner.cleaned(message, meID: "999@s.whatsapp.net", meLID: "999@lid")

		#expect(cleaned.from == "123@s.whatsapp.net")
		#expect(cleaned.participant == "456@lid")
	}

	@Test("normalizes incoming reaction keys from the sender perspective")
	func normalizesIncomingReactionKeysFromTheSenderPerspective() throws {
		let message = ReceivedMessage(
			id: "reaction-id",
			from: "group@g.us",
			timestamp: nil,
			content: .reaction(ReceivedReactionContent(
				key: ReceivedMessageKey(
					remoteJID: "111@s.whatsapp.net",
					fromMe: false,
					id: "target-id",
					participant: "999@s.whatsapp.net"
				),
				text: "👍",
				groupingKey: nil,
				senderTimestampMilliseconds: nil
			)),
			fromMe: false,
			keyParticipant: "111@s.whatsapp.net"
		)

		let cleaned = MessageCleaner.cleaned(message, meID: "999@s.whatsapp.net", meLID: "999@lid")
		guard case .reaction(let reaction) = cleaned.content else {
			Issue.record("expected reaction content")
			return
		}
		let key = try #require(reaction.key)

		#expect(key.remoteJID == "group@g.us")
		#expect(key.fromMe)
		#expect(key.participant == "999@s.whatsapp.net")
	}

	@Test("flips sender-owned reaction targets to non-self")
	func flipsSenderOwnedReactionTargetsToNonSelf() throws {
		let message = ReceivedMessage(
			id: "reaction-id",
			from: "group@g.us",
			timestamp: nil,
			content: .reaction(ReceivedReactionContent(
				key: ReceivedMessageKey(
					remoteJID: "group@g.us",
					fromMe: true,
					id: "target-id",
					participant: nil
				),
				text: "👍",
				groupingKey: nil,
				senderTimestampMilliseconds: nil
			)),
			fromMe: false,
			keyParticipant: "111@s.whatsapp.net"
		)

		let cleaned = MessageCleaner.cleaned(message, meID: "999@s.whatsapp.net", meLID: "999@lid")
		guard case .reaction(let reaction) = cleaned.content else {
			Issue.record("expected reaction content")
			return
		}
		let key = try #require(reaction.key)

		#expect(key.remoteJID == "group@g.us")
		#expect(!key.fromMe)
		#expect(key.participant == "111@s.whatsapp.net")
	}

	@Test("normalizes nested reaction participants before perspective checks")
	func normalizesNestedReactionParticipantsBeforePerspectiveChecks() throws {
		let message = ReceivedMessage(
			id: "reaction-id",
			from: "group@g.us",
			timestamp: nil,
			content: .reaction(ReceivedReactionContent(
				key: ReceivedMessageKey(
					remoteJID: "group@g.us",
					fromMe: false,
					id: "target-id",
					participant: "999:7@hosted"
				),
				text: "👍",
				groupingKey: nil,
				senderTimestampMilliseconds: nil
			)),
			fromMe: false,
			keyParticipant: "111:3@s.whatsapp.net"
		)

		let cleaned = MessageCleaner.cleaned(message, meID: "999@s.whatsapp.net", meLID: "999@lid")
		guard case .reaction(let reaction) = cleaned.content else {
			Issue.record("expected reaction content")
			return
		}
		let key = try #require(reaction.key)

		#expect(key.remoteJID == "group@g.us")
		#expect(key.fromMe)
		#expect(key.participant == "999@s.whatsapp.net")
	}

	@Test("keeps nested keys unchanged for own messages")
	func keepsNestedKeysUnchangedForOwnMessages() throws {
		let originalKey = ReceivedMessageKey(
			remoteJID: "target@s.whatsapp.net",
			fromMe: false,
			id: "target-id",
			participant: nil
		)
		let message = ReceivedMessage(
			id: "poll-update-id",
			from: "group@g.us",
			timestamp: nil,
			content: .pollUpdate(ReceivedPollUpdateContent(
				pollCreationMessageKey: originalKey,
				encryptedPayload: Data([0x01]),
				encryptedIV: Data([0x02]),
				senderTimestampMilliseconds: nil
			)),
			fromMe: true,
			keyParticipant: "111@s.whatsapp.net"
		)

		let cleaned = MessageCleaner.cleaned(message, meID: "999@s.whatsapp.net", meLID: "999@lid")
		guard case .pollUpdate(let update) = cleaned.content else {
			Issue.record("expected poll update content")
			return
		}

		#expect(update.pollCreationMessageKey == originalKey)
	}
}
