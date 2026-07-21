import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client message send")
struct WhatsAppClientMessageSendTests {
	@Test("sends text messages after resolving recipient devices")
	func sendsTextMessagesAfterResolvingRecipientDevices() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0x10, 0x20]))
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

		let messageID = try await client.sendTextMessage(
			to: "123@s.whatsapp.net",
			text: "hello from swift",
			messageID: "3EB0TEXTRESOLVED"
		)

		#expect(messageID == "3EB0TEXTRESOLVED")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		#expect(await callOrder.values == ["sessions", "encrypt:123.0@s.whatsapp.net"])
		#expect(await encryptor.calls.map(\.jid) == ["123.0@s.whatsapp.net"])
		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0TEXTRESOLVED")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
		#expect(stanza.firstChild(named: "participants")?.firstChild(named: "to")?.attrs["jid"] == "123.0@s.whatsapp.net")
	}

	@Test("attaches trusted contact tokens to one-to-one messages")
	func attachesTrustedContactTokensToOneToOneMessages() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let keys = InMemorySignalKeyStore(storage: [
			.tcToken: [
				"123@s.whatsapp.net": try TrustedContactTokenCoding.encode(TrustedContactToken(
					token: Data([0xaa, 0xbb]),
					timestamp: "9999999999"
				))
			]
		])
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: sampleMessageSendCredentials(), keys: keys),
			transportFactory: { _ in transport },
			messageEncryptor: StubMessageSendEncryptor(
				results: [EncryptedMessage(type: "msg", ciphertext: Data([0x10]))],
				callOrder: callOrder
			),
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendTextMessage(to: "123@s.whatsapp.net", text: "hello", messageID: "3EB0TCTOKEN")

		var codec = NoiseFrameCodec()
		let stanza = try BinaryNodeDecoder().decode(codec.decode(await transport.sentFrames[0])[0])
		#expect(stanza.firstChild(named: "tctoken")?.content == .data(Data([0xaa, 0xbb])))
	}

	@Test("issues trusted contact token after one-to-one message send")
	func issuesTrustedContactTokenAfterOneToOneMessageSend() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let keys = InMemorySignalKeyStore()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: sampleMessageSendCredentials(), keys: keys),
			transportFactory: { _ in transport },
			messageEncryptor: StubMessageSendEncryptor(
				results: [EncryptedMessage(type: "msg", ciphertext: Data([0x10]))],
				callOrder: callOrder
			),
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendTextMessage(to: "123@s.whatsapp.net", text: "hello", messageID: "3EB0ISSUETCTOKEN")

		var codec = NoiseFrameCodec()
		let request = try BinaryNodeDecoder().decode(codec.decode(await transport.waitForSentFrame(at: 1))[0])
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "privacy")
		#expect(request.firstChild(named: "tokens")?.firstChild(named: "token")?.attrs["jid"] == "123@s.whatsapp.net")
		#expect(request.firstChild(named: "tokens")?.firstChild(named: "token")?.attrs["type"] == "trusted_contact")

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": request.attrs["id"] ?? "", "type": "result"]))
		let stored = try await waitForStoredTrustedContactToken(keys: keys, jid: "123@s.whatsapp.net")
		#expect(stored.senderTimestamp != nil)
	}

	@Test("sends reaction messages after resolving recipient devices")
	func sendsReactionMessagesAfterResolvingRecipientDevices() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0x66]))
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

		let target = MessageReactionTarget(
			chatJID: "123@s.whatsapp.net",
			messageID: "3EB0TARGET",
			fromMe: false,
			participantJID: "456@s.whatsapp.net"
		)
		let messageID = try await client.sendReactionMessage(
			to: "123@s.whatsapp.net",
			reaction: "+1",
			target: target,
			timestampMilliseconds: 1_700_000_999_000,
			messageID: "3EB0REACTION"
		)

		#expect(messageID == "3EB0REACTION")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		#expect(await callOrder.values == ["sessions", "encrypt:123.0@s.whatsapp.net"])
		let encryptorCalls = await encryptor.calls
		let protobufMessage = try Proto_Message(serializedBytes: encryptorCalls[0].data.dropLast())
		#expect(protobufMessage.reactionMessage.text == "+1")
		#expect(protobufMessage.reactionMessage.senderTimestampMs == 1_700_000_999_000)
		#expect(protobufMessage.reactionMessage.key.remoteJid == "123@s.whatsapp.net")
		#expect(protobufMessage.reactionMessage.key.id == "3EB0TARGET")
		#expect(protobufMessage.reactionMessage.key.participant == "456@s.whatsapp.net")

		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0REACTION")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
	}

	@Test("sends location messages after resolving recipient devices")
	func sendsLocationMessagesAfterResolvingRecipientDevices() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0x77]))
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

		let messageID = try await client.sendLocationMessage(
			to: "123@s.whatsapp.net",
			location: OutgoingLocationContent(
				latitude: -25.966213,
				longitude: 32.56745,
				name: "Maputo Central",
				address: "Av. 25 de Setembro",
				url: "https://maps.example/maputo"
			),
			messageID: "3EB0LOCATION"
		)

		#expect(messageID == "3EB0LOCATION")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		#expect(await callOrder.values == ["sessions", "encrypt:123.0@s.whatsapp.net"])
		let encryptorCalls = await encryptor.calls
		let protobufMessage = try Proto_Message(serializedBytes: encryptorCalls[0].data.dropLast())
		#expect(protobufMessage.locationMessage.degreesLatitude == -25.966213)
		#expect(protobufMessage.locationMessage.degreesLongitude == 32.56745)
		#expect(protobufMessage.locationMessage.name == "Maputo Central")
		#expect(protobufMessage.locationMessage.address == "Av. 25 de Setembro")
		#expect(protobufMessage.locationMessage.url == "https://maps.example/maputo")

		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0LOCATION")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
	}

	@Test("sends contact messages after resolving recipient devices")
	func sendsContactMessagesAfterResolvingRecipientDevices() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0x88]))
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

		let contact = OutgoingContactContent(
			displayName: "Jane Swift",
			vcard: "BEGIN:VCARD\nVERSION:3.0\nFN:Jane Swift\nTEL;type=CELL;waid=258841234567:+258 84 123 4567\nEND:VCARD"
		)
		let messageID = try await client.sendContactMessage(
			to: "123@s.whatsapp.net",
			contact: contact,
			messageID: "3EB0CONTACT"
		)

		#expect(messageID == "3EB0CONTACT")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		#expect(await callOrder.values == ["sessions", "encrypt:123.0@s.whatsapp.net"])
		let encryptorCalls = await encryptor.calls
		let protobufMessage = try Proto_Message(serializedBytes: encryptorCalls[0].data.dropLast())
		#expect(protobufMessage.contactMessage.displayName == "Jane Swift")
		#expect(protobufMessage.contactMessage.vcard == contact.vcard)

		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0CONTACT")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
	}

	@Test("sends contacts array messages after resolving recipient devices")
	func sendsContactsArrayMessagesAfterResolvingRecipientDevices() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0x99]))
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

		let first = OutgoingContactContent(
			displayName: "Jane Swift",
			vcard: "BEGIN:VCARD\nVERSION:3.0\nFN:Jane Swift\nEND:VCARD"
		)
		let second = OutgoingContactContent(
			displayName: "John Swift",
			vcard: "BEGIN:VCARD\nVERSION:3.0\nFN:John Swift\nEND:VCARD"
		)
		let messageID = try await client.sendContactsMessage(
			to: "123@s.whatsapp.net",
			displayName: "Swift Contacts",
			contacts: [first, second],
			messageID: "3EB0CONTACTS"
		)

		#expect(messageID == "3EB0CONTACTS")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		#expect(await callOrder.values == ["sessions", "encrypt:123.0@s.whatsapp.net"])
		let encryptorCalls = await encryptor.calls
		let protobufMessage = try Proto_Message(serializedBytes: encryptorCalls[0].data.dropLast())
		#expect(protobufMessage.contactsArrayMessage.displayName == "Swift Contacts")
		#expect(protobufMessage.contactsArrayMessage.contacts.map { $0.displayName } == ["Jane Swift", "John Swift"])

		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0CONTACTS")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
	}

	@Test("sends poll messages after resolving recipient devices")
	func sendsPollMessagesAfterResolvingRecipientDevices() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0xaa]))
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

		let poll = OutgoingPollContent(
			name: "Best Swift feature?",
			options: ["Actors", "Macros", "AsyncSequence"],
			selectableOptionsCount: 1,
			encryptedKey: try Data(hexString: "000102030405060708090a0b0c0d0e0f")
		)
		let messageID = try await client.sendPollMessage(
			to: "123@s.whatsapp.net",
			poll: poll,
			messageID: "3EB0POLL"
		)

		#expect(messageID == "3EB0POLL")
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		#expect(await callOrder.values == ["sessions", "encrypt:123.0@s.whatsapp.net"])
		let encryptorCalls = await encryptor.calls
		let protobufMessage = try Proto_Message(serializedBytes: encryptorCalls[0].data.dropLast())
		#expect(protobufMessage.pollCreationMessageV3.name == "Best Swift feature?")
		#expect(protobufMessage.pollCreationMessageV3.options.map { $0.optionName } == ["Actors", "Macros", "AsyncSequence"])
		#expect(protobufMessage.pollCreationMessageV3.selectableOptionsCount == 1)

		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0POLL")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
	}

	@Test("rejects poll messages with selectable count above option count")
	func rejectsPollMessagesWithSelectableCountAboveOptionCount() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0xaa]))
		])
		let deviceResolver = StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"])
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: sessionPreparer
		)
		try await client.connect()

		let poll = OutgoingPollContent(
			name: "Best Swift feature?",
			options: ["Actors", "Macros"],
			selectableOptionsCount: 3
		)

		await #expect(throws: OutgoingPollContentValidationError.invalidSelectableOptionsCount(
			selectableOptionsCount: 3,
			optionCount: 2
		)) {
			try await client.sendPollMessage(to: "123@s.whatsapp.net", poll: poll, messageID: "3EB0BADPOLL")
		}
		#expect(await deviceResolver.calls.isEmpty)
		#expect(await sessionPreparer.calls.isEmpty)
		#expect(await encryptor.calls.isEmpty)
		#expect(await transport.sentFrames.isEmpty)
	}

}

actor StubMessageDeviceResolver: MessageDeviceResolving {
	private let result: [String]
	private(set) var calls: [String] = []

	init(result: [String]) {
		self.result = result
	}

	func deviceJIDs(for jid: String) async throws -> [String] {
		calls.append(jid)
		return result
	}
}

actor StubMessageSendEncryptor: MessageEncrypting {
	private let results: [EncryptedMessage]
	private let callOrder: MessageSendCallOrder?
	private var nextResultIndex = 0
	private(set) var calls: [MessageSendEncryptionCall] = []

	init(results: [EncryptedMessage], callOrder: MessageSendCallOrder? = nil) {
		self.results = results
		self.callOrder = callOrder
	}

	func encryptMessage(jid: String, data: Data) async throws -> EncryptedMessage {
		await callOrder?.append("encrypt:\(jid)")
		calls.append(MessageSendEncryptionCall(jid: jid, data: data))
		let result = results[nextResultIndex]
		nextResultIndex += 1
		return result
	}
}

actor MockMessageSendWebSocketTransport: WhatsAppWebSocketTransport {
	private(set) var sentFrames: [Data] = []
	private var inboundContinuations: [CheckedContinuation<Data?, Error>] = []
	private var inboundFrames: [Data?] = []

	func connect() async throws {}

	func send(_ data: Data) async throws {
		sentFrames.append(data)
	}

	func receive() async throws -> Data? {
		try await withCheckedThrowingContinuation { continuation in
			if !inboundFrames.isEmpty {
				continuation.resume(returning: inboundFrames.removeFirst())
			} else {
				inboundContinuations.append(continuation)
			}
		}
	}

	func close() async {
		resumeInbound(nil)
	}

	func waitForSentFrame(at index: Int = 0) async throws -> Data {
		for _ in 0..<200 where sentFrames.count <= index {
			try await Task.sleep(for: .milliseconds(1))
		}

		guard sentFrames.count > index else {
			throw MessageSendTestError.missingSentFrame
		}

		return sentFrames[index]
	}

	func enqueueInbound(_ node: BinaryNode) {
		let data = try! BinaryNodeEncoder().encode(node)
		var codec = NoiseFrameCodec()
		resumeInbound(codec.encode(data))
	}

	private func resumeInbound(_ data: Data?) {
		if inboundContinuations.isEmpty {
			inboundFrames.append(data)
		} else {
			inboundContinuations.removeFirst().resume(returning: data)
		}
	}
}

struct MessageSendEncryptionCall: Equatable, Sendable {
	let jid: String
	let data: Data
}

actor StubSignalSessionPreparer: SignalSessionPreparing {
	private let callOrder: MessageSendCallOrder
	private(set) var calls: [SignalSessionPreparationCall] = []

	init(callOrder: MessageSendCallOrder) {
		self.callOrder = callOrder
	}

	func assertSessions(for jids: [String], force: Bool) async throws -> Bool {
		await callOrder.append("sessions")
		calls.append(SignalSessionPreparationCall(jids: jids, force: force))
		return true
	}
}

struct SignalSessionPreparationCall: Equatable, Sendable {
	let jids: [String]
	let force: Bool
}

actor MessageSendCallOrder {
	private(set) var values: [String] = []

	func append(_ value: String) {
		values.append(value)
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw MessageSendTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}
}

private enum MessageSendTestError: Error {
	case invalidHex
	case missingSentFrame
	case missingTrustedContactToken
}

private func waitForStoredTrustedContactToken(
	keys: InMemorySignalKeyStore,
	jid: String
) async throws -> TrustedContactToken {
	for _ in 0..<200 {
		if let data = try await keys.get(.tcToken, ids: [jid])[jid],
		   let token = try? TrustedContactTokenCoding.decode(data) {
			return token
		}
		try await Task.sleep(for: .milliseconds(1))
	}

	throw MessageSendTestError.missingTrustedContactToken
}

private func sampleMessageSendCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32)),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data(repeating: 3, count: 32), publicKey: Data(repeating: 4, count: 32)),
		signedIdentityKey: AuthenticationKeyPair(privateKey: Data(repeating: 5, count: 32), publicKey: Data(repeating: 6, count: 32)),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(privateKey: Data(repeating: 7, count: 32), publicKey: Data(repeating: 8, count: 32)),
			signature: Data(repeating: 9, count: 64),
			keyID: 1
		),
		registrationID: 1,
		advSecretKey: "adv-secret",
		me: WhatsAppUser(id: "999@s.whatsapp.net"),
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true
	)
}
