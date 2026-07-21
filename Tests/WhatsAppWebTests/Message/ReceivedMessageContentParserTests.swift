import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message content parser")
struct ReceivedMessageContentParserTests {
	@Test("parses plain conversation text")
	func parsesPlainConversationText() throws {
		var message = Proto_Message()
		message.conversation = "hello from whatsapp"

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .text("hello from whatsapp"))
	}

	@Test("parses extended text")
	func parsesExtendedText() throws {
		let message = MessageContentBuilder.text("extended hello")

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .text("extended hello"))
	}

	@Test("parses future proof envelopes")
	func parsesFutureProofEnvelopes() throws {
		let inner = MessageContentBuilder.text("wrapped")

		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.ephemeralMessage = $1 })) == .text("wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(MessageContentBuilder.viewOnce(inner))) == .text("wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.documentWithCaptionMessage = $1 })) == .text("wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.viewOnceMessageV2 = $1 })) == .text("wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.viewOnceMessageV2Extension = $1 })) == .text("wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.editedMessage = $1 })) == .text("wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.associatedChildMessage = $1 })) == .text("wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.groupStatusMessage = $1 })) == .text("wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.groupStatusMessageV2 = $1 })) == .text("wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.statusMentionMessage = $1 })) == .text("wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.groupStatusMentionMessage = $1 })) == .text("wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.limitSharingMessage = $1 })) == .text("wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.botTaskMessage = $1 })) == .text("wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.questionMessage = $1 })) == .text("wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.botForwardedMessage = $1 })) == .text("wrapped"))
		#expect(try #require(ReceivedMessageContentParser.parse(futureProofMessage(inner) { $0.questionReplyMessage = $1 })) == .text("wrapped"))
	}

	@Test("parses device sent message envelopes")
	func parsesDeviceSentMessageEnvelopes() throws {
		var deviceSent = Proto_Message.DeviceSentMessage()
		deviceSent.destinationJid = "123@s.whatsapp.net"
		deviceSent.message = MessageContentBuilder.text("linked device")
		var message = Proto_Message()
		message.deviceSentMessage = deviceSent

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .text("linked device"))
	}

	@Test("parses template messages through extracted content")
	func parsesTemplateMessagesThroughExtractedContent() throws {
		var hydrated = Proto_Message.TemplateMessage.HydratedFourRowTemplate()
		hydrated.hydratedContentText = "Hydrated template text"
		var template = Proto_Message.TemplateMessage()
		template.hydratedTemplate = hydrated
		var message = Proto_Message()
		message.templateMessage = template

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .text("Hydrated template text"))
	}

	@Test("parses template media through extracted content")
	func parsesTemplateMediaThroughExtractedContent() throws {
		var location = Proto_Message.LocationMessage()
		location.name = "Maputo"
		location.degreesLatitude = -25.966213
		location.degreesLongitude = 32.573174
		var fourRow = Proto_Message.TemplateMessage.FourRowTemplate()
		fourRow.locationMessage = location
		var template = Proto_Message.TemplateMessage()
		template.fourRowTemplate = fourRow
		var message = Proto_Message()
		message.templateMessage = template

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .location(ReceivedLocationContent(
			latitude: -25.966213,
			longitude: 32.573174,
			name: "Maputo",
			address: nil,
			url: nil,
			accuracyInMeters: nil,
			comment: nil,
			jpegThumbnail: nil
		)))
	}

	@Test("parses location messages")
	func parsesLocationMessages() throws {
		var location = Proto_Message.LocationMessage()
		location.degreesLatitude = -25.966213
		location.degreesLongitude = 32.573174
		location.name = "Maputo Central Market"
		location.address = "Av. 25 de Setembro, Maputo"
		location.url = "https://maps.example/place"
		location.accuracyInMeters = 15
		location.comment = "meet here"
		location.jpegThumbnail = Data([0x0a, 0x0b])
		var message = Proto_Message()
		message.locationMessage = location

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .location(ReceivedLocationContent(
			latitude: -25.966213,
			longitude: 32.573174,
			name: "Maputo Central Market",
			address: "Av. 25 de Setembro, Maputo",
			url: "https://maps.example/place",
			accuracyInMeters: 15,
			comment: "meet here",
			jpegThumbnail: Data([0x0a, 0x0b])
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses live location messages")
	func parsesLiveLocationMessages() throws {
		var liveLocation = Proto_Message.LiveLocationMessage()
		liveLocation.degreesLatitude = -25.965331
		liveLocation.degreesLongitude = 32.589245
		liveLocation.accuracyInMeters = 8
		liveLocation.speedInMps = 4.5
		liveLocation.degreesClockwiseFromMagneticNorth = 91
		liveLocation.caption = "on my way"
		liveLocation.sequenceNumber = 42
		liveLocation.timeOffset = 120
		liveLocation.jpegThumbnail = Data([0x0c, 0x0d])
		var message = Proto_Message()
		message.liveLocationMessage = liveLocation

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .liveLocation(ReceivedLiveLocationContent(
			latitude: -25.965331,
			longitude: 32.589245,
			accuracyInMeters: 8,
			speedInMetersPerSecond: 4.5,
			degreesClockwiseFromMagneticNorth: 91,
			caption: "on my way",
			sequenceNumber: 42,
			timeOffsetSeconds: 120,
			jpegThumbnail: Data([0x0c, 0x0d])
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses contact messages")
	func parsesContactMessages() throws {
		var contact = Proto_Message.ContactMessage()
		contact.displayName = "Maria Silva"
		contact.vcard = "BEGIN:VCARD\nFN:Maria Silva\nTEL:+258840000000\nEND:VCARD"
		var message = Proto_Message()
		message.contactMessage = contact

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .contact(ReceivedContactContent(
			displayName: "Maria Silva",
			vcard: "BEGIN:VCARD\nFN:Maria Silva\nTEL:+258840000000\nEND:VCARD"
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses contact array messages")
	func parsesContactArrayMessages() throws {
		var first = Proto_Message.ContactMessage()
		first.displayName = "Maria Silva"
		first.vcard = "BEGIN:VCARD\nFN:Maria Silva\nTEL:+258840000000\nEND:VCARD"
		var second = Proto_Message.ContactMessage()
		second.displayName = "Joao Machel"
		second.vcard = "BEGIN:VCARD\nFN:Joao Machel\nTEL:+258850000000\nEND:VCARD"
		var contacts = Proto_Message.ContactsArrayMessage()
		contacts.displayName = "2 contacts"
		contacts.contacts = [first, second]
		var message = Proto_Message()
		message.contactsArrayMessage = contacts

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .contacts(ReceivedContactsContent(
			displayName: "2 contacts",
			contacts: [
				ReceivedContactContent(
					displayName: "Maria Silva",
					vcard: "BEGIN:VCARD\nFN:Maria Silva\nTEL:+258840000000\nEND:VCARD"
				),
				ReceivedContactContent(
					displayName: "Joao Machel",
					vcard: "BEGIN:VCARD\nFN:Joao Machel\nTEL:+258850000000\nEND:VCARD"
				)
			]
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses group invite messages")
	func parsesGroupInviteMessages() throws {
		var invite = Proto_Message.GroupInviteMessage()
		invite.groupJid = "1234567890@g.us"
		invite.inviteCode = "AbCdEfGhIjK"
		invite.inviteExpiration = 1_700_010_000
		invite.groupName = "Swift Baileys"
		invite.jpegThumbnail = Data([0x11, 0x12])
		invite.caption = "join the group"
		invite.groupType = .parent
		var message = Proto_Message()
		message.groupInviteMessage = invite

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .groupInvite(ReceivedGroupInviteContent(
			groupJID: "1234567890@g.us",
			inviteCode: "AbCdEfGhIjK",
			inviteExpiration: 1_700_010_000,
			groupName: "Swift Baileys",
			caption: "join the group",
			groupType: .parent,
			jpegThumbnail: Data([0x11, 0x12])
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses poll creation messages")
	func parsesPollCreationMessages() throws {
		var first = Proto_Message.PollCreationMessage.Option()
		first.optionName = "Swift"
		first.optionHash = "hash-swift"
		var second = Proto_Message.PollCreationMessage.Option()
		second.optionName = "TypeScript"
		second.optionHash = "hash-typescript"
		var correct = Proto_Message.PollCreationMessage.Option()
		correct.optionName = "Swift"
		correct.optionHash = "hash-swift"
		var poll = Proto_Message.PollCreationMessage()
		poll.encKey = Data([0x01, 0x02, 0x03])
		poll.name = "Best Baileys port?"
		poll.options = [first, second]
		poll.selectableOptionsCount = 1
		poll.pollContentType = .text
		poll.pollType = .quiz
		poll.correctAnswer = correct
		var message = Proto_Message()
		message.pollCreationMessage = poll

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .pollCreation(ReceivedPollCreationContent(
			name: "Best Baileys port?",
			options: [
				ReceivedPollOption(name: "Swift", hash: "hash-swift"),
				ReceivedPollOption(name: "TypeScript", hash: "hash-typescript")
			],
			selectableOptionsCount: 1,
			encryptedKey: Data([0x01, 0x02, 0x03]),
			contentType: .text,
			pollType: .quiz,
			correctAnswer: ReceivedPollOption(name: "Swift", hash: "hash-swift")
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses poll update messages")
	func parsesPollUpdateMessages() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "258840000000@s.whatsapp.net"
		key.fromMe = false
		key.id = "3EB0POLL"
		key.participant = "258841111111@s.whatsapp.net"
		var vote = Proto_Message.PollEncValue()
		vote.encPayload = Data([0x01, 0x02, 0x03])
		vote.encIv = Data([0x04, 0x05, 0x06])
		var pollUpdate = Proto_Message.PollUpdateMessage()
		pollUpdate.pollCreationMessageKey = key
		pollUpdate.vote = vote
		pollUpdate.senderTimestampMs = 1_700_002_000_000
		var message = Proto_Message()
		message.pollUpdateMessage = pollUpdate

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .pollUpdate(ReceivedPollUpdateContent(
			pollCreationMessageKey: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0POLL",
				participant: "258841111111@s.whatsapp.net"
			),
			encryptedPayload: Data([0x01, 0x02, 0x03]),
			encryptedIV: Data([0x04, 0x05, 0x06]),
			senderTimestampMilliseconds: 1_700_002_000_000
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses reaction messages")
	func parsesReactionMessages() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "258840000000@s.whatsapp.net"
		key.fromMe = false
		key.id = "3EB075A822D4810DF6AE2D"
		key.participant = "258850000000@s.whatsapp.net"
		var reaction = Proto_Message.ReactionMessage()
		reaction.key = key
		reaction.text = "+1"
		reaction.groupingKey = "3EB075A822D4810DF6AE2D"
		reaction.senderTimestampMs = 1_700_000_999_000
		var message = Proto_Message()
		message.reactionMessage = reaction

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .reaction(ReceivedReactionContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB075A822D4810DF6AE2D",
				participant: "258850000000@s.whatsapp.net"
			),
			text: "+1",
			groupingKey: "3EB075A822D4810DF6AE2D",
			senderTimestampMilliseconds: 1_700_000_999_000
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses revoked protocol messages")
	func parsesRevokedProtocolMessages() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "258840000000@s.whatsapp.net"
		key.fromMe = true
		key.id = "3EB0REVOKED"
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .revoke
		protocolMessage.key = key
		protocolMessage.timestampMs = 1_700_001_000_000
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .messageRevoked(ReceivedMessageRevokedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: true,
				id: "3EB0REVOKED",
				participant: nil
			),
			timestampMilliseconds: 1_700_001_000_000
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses edited protocol messages")
	func parsesEditedProtocolMessages() throws {
		var key = Proto_MessageKey()
		key.remoteJid = "258840000000@s.whatsapp.net"
		key.fromMe = false
		key.id = "3EB0EDITED"
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .messageEdit
		protocolMessage.key = key
		protocolMessage.editedMessage = MessageContentBuilder.text("edited text")
		protocolMessage.timestampMs = 1_700_001_111_000
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .messageEdited(ReceivedMessageEditedContent(
			key: ReceivedMessageKey(
				remoteJID: "258840000000@s.whatsapp.net",
				fromMe: false,
				id: "3EB0EDITED",
				participant: nil
			),
			content: .text("edited text"),
			timestampMilliseconds: 1_700_001_111_000
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}
}

func futureProofMessage(
	_ inner: Proto_Message,
	assign: (inout Proto_Message, Proto_Message.FutureProofMessage) -> Void
) -> Proto_Message {
	var futureProof = Proto_Message.FutureProofMessage()
	futureProof.message = inner
	var message = Proto_Message()
	assign(&message, futureProof)
	return message
}
