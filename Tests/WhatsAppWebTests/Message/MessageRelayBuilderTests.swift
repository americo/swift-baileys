import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Message relay builder")
struct MessageRelayBuilderTests {
	@Test("builds direct message stanza with encrypted participant nodes")
	func buildsDirectMessageStanzaWithEncryptedParticipantNodes() async throws {
		let encryptor = RecordingMessageEncryptor(
			results: [
				EncryptedMessage(type: "msg", ciphertext: Data([0xaa, 0x01])),
				EncryptedMessage(type: "pkmsg", ciphertext: Data([0xbb, 0x02]))
			]
		)
		let builder = MessageRelayBuilder(
			encoder: MessageEncoder(randomByte: { 0x00 }),
			encryptor: encryptor
		)
		let message = MessageContentBuilder.text("hello from swift")

		let stanza = try await builder.buildDirectMessageStanza(
			to: "123@s.whatsapp.net",
			messageID: "3EB0TESTMESSAGEID",
			message: message,
			recipientDeviceJIDs: ["123.0@s.whatsapp.net", "456.0@s.whatsapp.net"]
		)

		let encodedMessage = try MessageEncoder(randomByte: { 0x00 }).encode(message)
		#expect(await encryptor.calls == [
			MessageEncryptionCall(jid: "123.0@s.whatsapp.net", data: encodedMessage),
			MessageEncryptionCall(jid: "456.0@s.whatsapp.net", data: encodedMessage)
		])
		#expect(
			stanza == BinaryNode(
				tag: "message",
				attrs: [
					"id": "3EB0TESTMESSAGEID",
					"to": "123@s.whatsapp.net",
					"type": "text",
					"phash": "2:/wfv8V"
				],
				content: .nodes([
					BinaryNode(
						tag: "participants",
						content: .nodes([
							BinaryNode(
								tag: "to",
								attrs: ["jid": "123.0@s.whatsapp.net"],
								content: .nodes([
									BinaryNode(tag: "enc", attrs: ["v": "2", "type": "msg"], content: .data(Data([0xaa, 0x01])))
								])
							),
							BinaryNode(
								tag: "to",
								attrs: ["jid": "456.0@s.whatsapp.net"],
								content: .nodes([
									BinaryNode(tag: "enc", attrs: ["v": "2", "type": "pkmsg"], content: .data(Data([0xbb, 0x02])))
								])
							)
						])
					)
				])
			)
		)
	}

	@Test("adds participant hash for direct relay recipients")
	func addsParticipantHashForDirectRelayRecipients() async throws {
		let builder = MessageRelayBuilder(
			encoder: MessageEncoder(randomByte: { 0x00 }),
			encryptor: RecordingMessageEncryptor(results: [
				EncryptedMessage(type: "msg", ciphertext: Data([0xaa])),
				EncryptedMessage(type: "msg", ciphertext: Data([0xbb]))
			])
		)

		let stanza = try await builder.buildDirectMessageStanza(
			to: "123@s.whatsapp.net",
			messageID: "3EB0PHASH",
			message: MessageContentBuilder.text("hello"),
			recipientDeviceJIDs: ["456.0@s.whatsapp.net", "123.0@s.whatsapp.net"]
		)

		#expect(stanza.attrs["phash"] == ParticipantHashGenerator.generateV2(participants: [
			"456.0@s.whatsapp.net",
			"123.0@s.whatsapp.net"
		]))
	}

	@Test("preserves explicit participant hash attribute")
	func preservesExplicitParticipantHashAttribute() async throws {
		let builder = MessageRelayBuilder(
			encoder: MessageEncoder(randomByte: { 0x00 }),
			encryptor: RecordingMessageEncryptor(results: [EncryptedMessage(type: "msg", ciphertext: Data([0xaa]))])
		)

		let stanza = try await builder.buildDirectMessageStanza(
			to: "123@s.whatsapp.net",
			messageID: "3EB0PHASHOVERRIDE",
			message: MessageContentBuilder.text("hello"),
			recipientDeviceJIDs: ["123.0@s.whatsapp.net"],
			additionalAttributes: ["phash": "2:manual"]
		)

		#expect(stanza.attrs["phash"] == "2:manual")
	}

	@Test("rejects direct relay without recipient devices")
	func rejectsDirectRelayWithoutRecipientDevices() async {
		let builder = MessageRelayBuilder(
			encoder: MessageEncoder(randomByte: { 0x00 }),
			encryptor: RecordingMessageEncryptor(results: [])
		)

		await #expect(throws: MessageRelayBuilderError.missingRecipientDevices) {
			try await builder.buildDirectMessageStanza(
				to: "123@s.whatsapp.net",
				messageID: "3EB0TESTMESSAGEID",
				message: MessageContentBuilder.text("hello"),
				recipientDeviceJIDs: []
			)
		}
	}

	@Test("rejects empty direct ciphertext before relay assembly")
	func rejectsEmptyDirectCiphertextBeforeRelayAssembly() async {
		let builder = MessageRelayBuilder(
			encoder: MessageEncoder(randomByte: { 0x00 }),
			encryptor: RecordingMessageEncryptor(results: [EncryptedMessage(type: "msg", ciphertext: Data())])
		)

		await #expect(throws: MessageRelayBuilderError.emptyDirectCiphertext) {
			try await builder.buildDirectMessageStanza(
				to: "123@s.whatsapp.net",
				messageID: "3EB0EMPTYDIRECT",
				message: MessageContentBuilder.text("hello"),
				recipientDeviceJIDs: ["123.0@s.whatsapp.net"]
			)
		}
	}

	@Test("appends additional relay nodes after participants")
	func appendsAdditionalRelayNodesAfterParticipants() async throws {
		let builder = MessageRelayBuilder(
			encoder: MessageEncoder(randomByte: { 0x00 }),
			encryptor: RecordingMessageEncryptor(results: [EncryptedMessage(type: "msg", ciphertext: Data([1]))])
		)

		let stanza = try await builder.buildDirectMessageStanza(
			to: "123@s.whatsapp.net",
			messageID: "3EB0TESTMESSAGEID",
			message: MessageContentBuilder.text("hello"),
			recipientDeviceJIDs: ["123.0@s.whatsapp.net"],
			additionalNodes: [BinaryNode(tag: "tctoken", content: .data(Data([7, 8])))]
		)

		guard case let .nodes(children) = stanza.content else {
			Issue.record("expected message child nodes")
			return
		}
		#expect(children.map(\.tag) == ["participants", "tctoken"])
		#expect(children[1].content == .data(Data([7, 8])))
	}

	@Test("creates participant nodes with extra encryption attributes")
	func createsParticipantNodesWithExtraEncryptionAttributes() async throws {
		let builder = MessageRelayBuilder(
			encoder: MessageEncoder(randomByte: { 0x00 }),
			encryptor: RecordingMessageEncryptor(results: [
				EncryptedMessage(type: "pkmsg", ciphertext: Data([0x0a])),
				EncryptedMessage(type: "msg", ciphertext: Data([0x0b]))
			])
		)

		let result = try await builder.createParticipantNodes(
			recipientDeviceJIDs: ["111:0@s.whatsapp.net", "222:0@s.whatsapp.net"],
			message: MessageContentBuilder.text("participant nodes"),
			extraAttributes: ["mediatype": "image"]
		)

		#expect(result.shouldIncludeDeviceIdentity)
		#expect(result.nodes.map { $0.attrs["jid"] } == ["111:0@s.whatsapp.net", "222:0@s.whatsapp.net"])
		#expect(result.nodes[0].firstChild(named: "enc")?.attrs["type"] == "pkmsg")
		#expect(result.nodes[0].firstChild(named: "enc")?.attrs["mediatype"] == "image")
		#expect(result.nodes[1].firstChild(named: "enc")?.attrs["type"] == "msg")
	}

	@Test("rejects empty retry ciphertext before relay assembly")
	func rejectsEmptyRetryCiphertextBeforeRelayAssembly() async {
		let builder = MessageRelayBuilder(
			encoder: MessageEncoder(randomByte: { 0x00 }),
			encryptor: RecordingMessageEncryptor(results: [EncryptedMessage(type: "msg", ciphertext: Data())])
		)

		await #expect(throws: MessageRelayBuilderError.emptyDirectCiphertext) {
			try await builder.buildRetryMessageStanza(
				to: "123@s.whatsapp.net",
				messageID: "3EB0EMPTYRETRY",
				message: MessageContentBuilder.text("hello"),
				participantJID: "123.0@s.whatsapp.net",
				retryCount: 1,
				localUserJID: nil,
				localUserLID: nil
			)
		}
	}

	@Test("wraps own-device direct messages in device sent envelope")
	func wrapsOwnDeviceDirectMessagesInDeviceSentEnvelope() async throws {
		let encryptor = RecordingMessageEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0xaa])),
			EncryptedMessage(type: "msg", ciphertext: Data([0xbb]))
		])
		let builder = MessageRelayBuilder(
			encoder: MessageEncoder(randomByte: { 0x00 }),
			encryptor: encryptor
		)
		let message = MessageContentBuilder.text("sync to my device")

		_ = try await builder.buildDirectMessageStanza(
			to: "222@s.whatsapp.net",
			messageID: "3EB0DSM",
			message: message,
			recipientDeviceJIDs: ["111:1@s.whatsapp.net", "222:0@s.whatsapp.net"],
			localJID: "111@s.whatsapp.net"
		)

		let calls = await encryptor.calls
		#expect(calls.map(\.jid) == ["111:1@s.whatsapp.net", "222:0@s.whatsapp.net"])
		let ownDeviceMessage = try Proto_Message(serializedBytes: calls[0].data.dropLast())
		#expect(ownDeviceMessage.deviceSentMessage.destinationJid == "222@s.whatsapp.net")
		#expect(ownDeviceMessage.deviceSentMessage.message.extendedTextMessage.text == "sync to my device")
		let otherDeviceMessage = try Proto_Message(serializedBytes: calls[1].data.dropLast())
		#expect(!otherDeviceMessage.hasDeviceSentMessage)
		#expect(otherDeviceMessage.extendedTextMessage.text == "sync to my device")
	}

	@Test("does not wrap peer data messages in device sent envelope")
	func doesNotWrapPeerDataMessagesInDeviceSentEnvelope() async throws {
		let encryptor = RecordingMessageEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0xaa]))
		])
		let builder = MessageRelayBuilder(
			encoder: MessageEncoder(randomByte: { 0x00 }),
			encryptor: encryptor
		)
		let message = MessageContentBuilder.text("peer data")

		_ = try await builder.buildDirectMessageStanza(
			to: "555@s.whatsapp.net",
			messageID: "3EB0PEERDATA",
			message: message,
			recipientDeviceJIDs: ["555:0@s.whatsapp.net"],
			localJID: "555@s.whatsapp.net",
			additionalAttributes: ["category": "peer"]
		)

		let call = try #require(await encryptor.calls.first)
		let encryptedMessage = try Proto_Message(serializedBytes: call.data.dropLast())
		#expect(!encryptedMessage.hasDeviceSentMessage)
		#expect(encryptedMessage.extendedTextMessage.text == "peer data")
	}

	@Test("appends reporting token for direct messages with message secret")
	func appendsReportingTokenForDirectMessagesWithMessageSecret() async throws {
		let builder = MessageRelayBuilder(
			encoder: MessageEncoder(randomByte: { 0x0f }),
			encryptor: RecordingMessageEncryptor(results: [EncryptedMessage(type: "msg", ciphertext: Data([0xaa]))])
		)
		let secret = try Data(relayHex: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
		var context = Proto_MessageContextInfo()
		context.messageSecret = secret
		var text = Proto_Message.ExtendedTextMessage()
		text.text = "hello reporting"
		text.matchedText = "https://example.com"
		text.description_p = "Desc"
		text.title = "Example"
		var message = Proto_Message()
		message.extendedTextMessage = text
		message.messageContextInfo = context

		let stanza = try await builder.buildDirectMessageStanza(
			to: "222@s.whatsapp.net",
			messageID: "3EB0REPORT",
			message: message,
			recipientDeviceJIDs: ["222.0@s.whatsapp.net"]
		)

		guard case let .nodes(children) = stanza.content else {
			Issue.record("expected message child nodes")
			return
		}
		#expect(children.map(\.tag) == ["participants", "reporting"])
		#expect(children[1] == BinaryNode(
			tag: "reporting",
			content: .nodes([
				BinaryNode(
					tag: "reporting_token",
					attrs: ["v": "2"],
					content: .data(try Data(relayHex: "8272388ab760913c508a8ad00718f024"))
				)
			])
		))
	}

	@Test("builds group message stanza with sender key encryption and distribution")
	func buildsGroupMessageStanzaWithSenderKeyEncryptionAndDistribution() async throws {
		let directEncryptor = RecordingMessageEncryptor(
			results: [EncryptedMessage(type: "pkmsg", ciphertext: Data([0x41, 0x42]))]
		)
		let groupEncryptor = RecordingGroupMessageEncryptor(
			result: EncryptedGroupMessage(
				ciphertext: Data([0xaa, 0xbb]),
				senderKeyDistributionMessage: Data([0x99, 0x88])
			)
		)
		let builder = MessageRelayBuilder(
			encoder: MessageEncoder(randomByte: { 0x00 }),
			encryptor: directEncryptor,
			groupEncryptor: groupEncryptor
		)
		let message = MessageContentBuilder.text("hello group")

		let stanza = try await builder.buildGroupMessageStanza(
			to: "111-222@g.us",
			messageID: "3EB0GROUPMESSAGE",
			message: message,
			senderJID: "123@s.whatsapp.net",
			senderKeyRecipientDeviceJIDs: ["456.0@s.whatsapp.net"]
		)

		let encodedMessage = try MessageEncoder(randomByte: { 0x00 }).encode(message)
		#expect(await groupEncryptor.calls == [
			GroupMessageEncryptionCall(group: "111-222@g.us", senderJID: "123@s.whatsapp.net", data: encodedMessage)
		])

		let directCall = try #require(await directEncryptor.calls.first)
		let senderKeyMessage = try Proto_Message(serializedBytes: directCall.data.dropLast())
		#expect(directCall.jid == "456.0@s.whatsapp.net")
		#expect(senderKeyMessage.senderKeyDistributionMessage.groupID == "111-222@g.us")
		#expect(senderKeyMessage.senderKeyDistributionMessage.axolotlSenderKeyDistributionMessage == Data([0x99, 0x88]))
		#expect(
			stanza == BinaryNode(
				tag: "message",
				attrs: ["id": "3EB0GROUPMESSAGE", "to": "111-222@g.us", "type": "text"],
				content: .nodes([
					BinaryNode(
						tag: "participants",
						content: .nodes([
							BinaryNode(
								tag: "to",
								attrs: ["jid": "456.0@s.whatsapp.net"],
								content: .nodes([
									BinaryNode(tag: "enc", attrs: ["v": "2", "type": "pkmsg"], content: .data(Data([0x41, 0x42])))
								])
							)
						])
					),
					BinaryNode(
						tag: "enc",
						attrs: ["v": "2", "type": "skmsg"],
						content: .data(Data([0xaa, 0xbb]))
					)
				])
			)
		)
	}

	@Test("rejects empty group encryption outputs before relay assembly")
	func rejectsEmptyGroupEncryptionOutputsBeforeRelayAssembly() async {
		let emptyGroupBuilder = MessageRelayBuilder(
			encoder: MessageEncoder(randomByte: { 0x00 }),
			encryptor: RecordingMessageEncryptor(results: []),
			groupEncryptor: RecordingGroupMessageEncryptor(
				result: EncryptedGroupMessage(ciphertext: Data(), senderKeyDistributionMessage: Data([0x01]))
			)
		)
		await #expect(throws: MessageRelayBuilderError.emptyGroupCiphertext) {
			try await emptyGroupBuilder.buildGroupMessageStanza(
				to: "111-222@g.us",
				messageID: "3EB0EMPTYGROUP",
				message: MessageContentBuilder.text("hello"),
				senderJID: "123@s.whatsapp.net",
				senderKeyRecipientDeviceJIDs: []
			)
		}

		let emptyDistributionBuilder = MessageRelayBuilder(
			encoder: MessageEncoder(randomByte: { 0x00 }),
			encryptor: RecordingMessageEncryptor(results: []),
			groupEncryptor: RecordingGroupMessageEncryptor(
				result: EncryptedGroupMessage(ciphertext: Data([0x01]), senderKeyDistributionMessage: Data())
			)
		)
		await #expect(throws: MessageRelayBuilderError.emptySenderKeyDistributionMessage) {
			try await emptyDistributionBuilder.buildGroupMessageStanza(
				to: "111-222@g.us",
				messageID: "3EB0EMPTYDISTRIBUTION",
				message: MessageContentBuilder.text("hello"),
				senderJID: "123@s.whatsapp.net",
				senderKeyRecipientDeviceJIDs: ["456.0@s.whatsapp.net"]
			)
		}
	}

	@Test("appends reporting token for group messages with message secret")
	func appendsReportingTokenForGroupMessagesWithMessageSecret() async throws {
		let builder = MessageRelayBuilder(
			encoder: MessageEncoder(randomByte: { 0x0f }),
			encryptor: RecordingMessageEncryptor(results: []),
			groupEncryptor: RecordingGroupMessageEncryptor(
				result: EncryptedGroupMessage(ciphertext: Data([0xaa]), senderKeyDistributionMessage: Data())
			)
		)
		let secret = try Data(relayHex: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
		var context = Proto_MessageContextInfo()
		context.messageSecret = secret
		var text = Proto_Message.ExtendedTextMessage()
		text.text = "hello reporting"
		text.matchedText = "https://example.com"
		text.description_p = "Desc"
		text.title = "Example"
		var message = Proto_Message()
		message.extendedTextMessage = text
		message.messageContextInfo = context

		let stanza = try await builder.buildGroupMessageStanza(
			to: "111-222@g.us",
			messageID: "3EB0REPORT",
			message: message,
			senderJID: "123@s.whatsapp.net",
			senderKeyRecipientDeviceJIDs: []
		)

		guard case let .nodes(children) = stanza.content else {
			Issue.record("expected message child nodes")
			return
		}
		#expect(children.map(\.tag) == ["enc", "reporting"])
		#expect(children[1] == BinaryNode(
			tag: "reporting",
			content: .nodes([
				BinaryNode(
					tag: "reporting_token",
					attrs: ["v": "2"],
					content: .data(try Data(relayHex: "234703f6cdb974d3457a2f1dd440c49e"))
				)
			])
		))
	}
}

private actor RecordingMessageEncryptor: MessageEncrypting {
	private let results: [EncryptedMessage]
	private var nextResultIndex = 0
	private(set) var calls: [MessageEncryptionCall] = []

	init(results: [EncryptedMessage]) {
		self.results = results
	}

	func encryptMessage(jid: String, data: Data) async throws -> EncryptedMessage {
		calls.append(MessageEncryptionCall(jid: jid, data: data))
		let result = results[nextResultIndex]
		nextResultIndex += 1
		return result
	}
}

private struct MessageEncryptionCall: Equatable, Sendable {
	let jid: String
	let data: Data
}

private actor RecordingGroupMessageEncryptor: GroupMessageEncrypting {
	private let result: EncryptedGroupMessage
	private(set) var calls: [GroupMessageEncryptionCall] = []

	init(result: EncryptedGroupMessage) {
		self.result = result
	}

	func encryptGroupMessage(group: String, senderJID: String, data: Data) async throws -> EncryptedGroupMessage {
		calls.append(GroupMessageEncryptionCall(group: group, senderJID: senderJID, data: data))
		return result
	}
}

private struct GroupMessageEncryptionCall: Equatable, Sendable {
	let group: String
	let senderJID: String
	let data: Data
}

private extension Data {
	init(relayHex hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw MessageRelayBuilderTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}
}

private enum MessageRelayBuilderTestError: Error {
	case invalidHex
}
