import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Outgoing message context")
struct OutgoingMessageContextTests {
	private let context = OutgoingMessageContext(isForwarded: true, forwardingScore: 3, ephemeralExpiration: 86_400)

	@Test("no context leaves the message alone")
	func noContext() {
		var message = Proto_Message()
		message.conversation = "hi"
		#expect(MessageContentBuilder.applying(.none, to: message) == message)
	}

	@Test("plain text becomes extended text, the only form with a context")
	func plainText() {
		var message = Proto_Message()
		message.conversation = "hi"
		let result = MessageContentBuilder.applying(context, to: message)
		#expect(!result.hasConversation)
		#expect(result.extendedTextMessage.text == "hi")
		#expect(result.extendedTextMessage.contextInfo.isForwarded)
		#expect(result.extendedTextMessage.contextInfo.forwardingScore == 3)
		#expect(result.extendedTextMessage.contextInfo.expiration == 86_400)
	}

	@Test("contact cards and locations carry it too")
	func contactAndLocation() {
		let contact = MessageContentBuilder.applying(
			context,
			to: MessageContentBuilder.contact(OutgoingContactContent(displayName: "Ana", vcard: "BEGIN:VCARD"))
		)
		#expect(contact.contactMessage.contextInfo.isForwarded)

		let location = MessageContentBuilder.applying(
			context,
			to: MessageContentBuilder.location(OutgoingLocationContent(latitude: 1, longitude: 2))
		)
		#expect(location.locationMessage.contextInfo.expiration == 86_400)
	}

	@Test("a poll keeps the secret its votes are encrypted with")
	func poll() throws {
		let secret = Data(repeating: 7, count: 32)
		let poll = try MessageContentBuilder.poll(OutgoingPollContent(
			name: "Lunch?", options: ["Yes", "No"], selectableOptionsCount: 1, messageSecret: secret
		))
		let result = MessageContentBuilder.applying(OutgoingMessageContext(ephemeralExpiration: 604_800), to: poll)
		#expect(result.pollCreationMessageV3.contextInfo.expiration == 604_800)
		#expect(result.messageContextInfo.messageSecret == secret)
		#expect(!result.pollCreationMessageV3.contextInfo.isForwarded)
	}

	@Test("a received message reports what its context says")
	func received() {
		var text = Proto_Message.ExtendedTextMessage()
		text.text = "hi"
		text.contextInfo.isForwarded = true
		text.contextInfo.forwardingScore = 5
		text.contextInfo.expiration = 7_776_000
		var message = Proto_Message()
		message.extendedTextMessage = text
		#expect(ReceivedWebMessageInfoParser.isForwarded(message))
		#expect(ReceivedWebMessageInfoParser.forwardingScore(of: message) == 5)
		#expect(ReceivedWebMessageInfoParser.ephemeralExpiration(of: message) == 7_776_000)
	}

	@Test("a vote is a poll stanza that is dropped when it cannot be read")
	func voteStanza() {
		var message = Proto_Message()
		message.pollUpdateMessage = Proto_Message.PollUpdateMessage()
		#expect(MessageStanzaClassifier.stanzaType(for: message) == "poll")
		#expect(MessageStanzaClassifier.encAttributes(for: message) == ["decrypt-fail": "hide"])
	}

	@Test("a vote names its option the way a received vote is matched, and reads back")
	func voteRoundTrip() throws {
		let hashes = ["Sim", "Não"].map(PollVoteCipher.optionHash)
		let cipher = PollVoteCipher()
		let secret = Data(repeating: 9, count: 32)
		let encrypted = try cipher.encrypt(
			selectedOptionHashes: hashes, pollMessageID: "poll", pollCreatorJID: "1@s.whatsapp.net",
			voterJID: "2@s.whatsapp.net", pollEncKey: secret
		)
		let read = try cipher.decrypt(
			encrypted, pollMessageID: "poll", pollCreatorJID: "1@s.whatsapp.net",
			voterJID: "2@s.whatsapp.net", pollEncKey: secret
		)
		#expect(read == hashes)
	}

	@Test("a message with no context reports nothing")
	func receivedPlain() {
		var message = Proto_Message()
		message.conversation = "hi"
		#expect(!ReceivedWebMessageInfoParser.isForwarded(message))
		#expect(ReceivedWebMessageInfoParser.forwardingScore(of: message) == nil)
		#expect(ReceivedWebMessageInfoParser.ephemeralExpiration(of: message) == nil)
	}
}
