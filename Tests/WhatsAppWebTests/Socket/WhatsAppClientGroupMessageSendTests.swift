import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client group message send")
struct WhatsAppClientGroupMessageSendTests {
	@Test("sends group text messages with sender key encryption")
	func sendsGroupTextMessagesWithSenderKeyEncryption() async throws {
		let transport = MockGroupMessageSendTransport()
		let callOrder = MessageSendCallOrder()
		let directEncryptor = StubMessageSendEncryptor(
			results: [
				EncryptedMessage(type: "pkmsg", ciphertext: Data([0x41])),
				EncryptedMessage(type: "msg", ciphertext: Data([0x42]))
			],
			callOrder: callOrder
		)
		let groupEncryptor = StubGroupMessageEncryptor(
			result: EncryptedGroupMessage(
				ciphertext: Data([0xaa, 0xbb]),
				senderKeyDistributionMessage: Data([0x99, 0x88])
			),
			callOrder: callOrder
		)
		let deviceResolver = StubGroupDeviceResolver(results: [
			"111@s.whatsapp.net": ["111:0@s.whatsapp.net"],
			"222@s.whatsapp.net": ["222:0@s.whatsapp.net"]
		])
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: sampleGroupMessageCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport },
			messageEncryptor: directEncryptor,
			groupMessageEncryptor: groupEncryptor,
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: sessionPreparer,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		let sendTask = Task {
			try await client.sendTextMessage(
				to: "120363000000000000@g.us",
				text: "hello group",
				messageID: "3EB0GROUPTEXT"
			)
		}
		let metadataRequest = try await transport.waitForSentNode(at: 0)
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": try #require(metadataRequest.attrs["id"]), "type": "result"],
			content: .nodes([groupMessageNode()])
		))
		let messageID = try await sendTask.value

		#expect(messageID == "3EB0GROUPTEXT")
		#expect(await deviceResolver.calls == ["111@s.whatsapp.net", "222@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["111:0@s.whatsapp.net", "222:0@s.whatsapp.net"], force: false)
		])
		#expect(await callOrder.values == [
			"sessions",
			"group:120363000000000000@g.us",
			"encrypt:111:0@s.whatsapp.net",
			"encrypt:222:0@s.whatsapp.net"
		])

		let stanza = try await transport.waitForSentNode(at: 1)
		#expect(stanza.attrs["id"] == "3EB0GROUPTEXT")
		#expect(stanza.attrs["to"] == "120363000000000000@g.us")
		#expect(stanza.attrs["addressing_mode"] == "lid")
		let participants = try #require(stanza.firstChild(named: "participants"))
		#expect(participants.children(named: "to").map { $0.attrs["jid"] } == [
			"111:0@s.whatsapp.net",
			"222:0@s.whatsapp.net"
		])
		let encrypted = try #require(stanza.firstChild(named: "enc"))
		#expect(encrypted.attrs["type"] == "skmsg")
		#expect(encrypted.content == .data(Data([0xaa, 0xbb])))
	}

	@Test("sends group poll messages with sender key encryption")
	func sendsGroupPollMessagesWithSenderKeyEncryption() async throws {
		let transport = MockGroupMessageSendTransport()
		let callOrder = MessageSendCallOrder()
		let directEncryptor = StubMessageSendEncryptor(
			results: [
				EncryptedMessage(type: "pkmsg", ciphertext: Data([0x51])),
				EncryptedMessage(type: "msg", ciphertext: Data([0x52]))
			],
			callOrder: callOrder
		)
		let groupEncryptor = StubGroupMessageEncryptor(
			result: EncryptedGroupMessage(
				ciphertext: Data([0xcc, 0xdd]),
				senderKeyDistributionMessage: Data([0x77, 0x66])
			),
			callOrder: callOrder
		)
		let deviceResolver = StubGroupDeviceResolver(results: [
			"111@s.whatsapp.net": ["111:0@s.whatsapp.net"],
			"222@s.whatsapp.net": ["222:0@s.whatsapp.net"],
			"120363000000000000@g.us": ["120363000000000000:0@g.us"]
		])
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: sampleGroupMessageCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport },
			messageEncryptor: directEncryptor,
			groupMessageEncryptor: groupEncryptor,
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: sessionPreparer,
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		let sendTask = Task {
			try await client.sendPollMessage(
				to: "120363000000000000@g.us",
				poll: OutgoingPollContent(name: "Group poll", options: ["One", "Two"], selectableOptionsCount: 1),
				messageID: "3EB0GROUPPOLL"
			)
		}
		let metadataRequest = try await transport.waitForSentNode(at: 0)
		#expect(metadataRequest.tag == "iq")
		guard metadataRequest.tag == "iq" else {
			return
		}

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": try #require(metadataRequest.attrs["id"]), "type": "result"],
			content: .nodes([groupMessageNode()])
		))
		let messageID = try await sendTask.value

		#expect(messageID == "3EB0GROUPPOLL")
		#expect(await deviceResolver.calls == ["111@s.whatsapp.net", "222@s.whatsapp.net"])
		#expect(await callOrder.values == [
			"sessions",
			"group:120363000000000000@g.us",
			"encrypt:111:0@s.whatsapp.net",
			"encrypt:222:0@s.whatsapp.net"
		])

		let stanza = try await transport.waitForSentNode(at: 1)
		#expect(stanza.attrs["id"] == "3EB0GROUPPOLL")
		#expect(stanza.attrs["to"] == "120363000000000000@g.us")
		let encrypted = try #require(stanza.firstChild(named: "enc"))
		#expect(encrypted.attrs["type"] == "skmsg")
		#expect(encrypted.content == .data(Data([0xcc, 0xdd])))
	}
}

private actor StubGroupMessageEncryptor: GroupMessageEncrypting {
	private let result: EncryptedGroupMessage
	private let callOrder: MessageSendCallOrder
	private(set) var calls: [GroupMessageEncryptionCall] = []

	init(result: EncryptedGroupMessage, callOrder: MessageSendCallOrder) {
		self.result = result
		self.callOrder = callOrder
	}

	func encryptGroupMessage(group: String, senderJID: String, data: Data) async throws -> EncryptedGroupMessage {
		await callOrder.append("group:\(group)")
		calls.append(GroupMessageEncryptionCall(group: group, senderJID: senderJID, data: data))
		return result
	}
}

private struct GroupMessageEncryptionCall: Equatable, Sendable {
	let group: String
	let senderJID: String
	let data: Data
}

private actor StubGroupDeviceResolver: MessageDeviceResolving {
	private let results: [String: [String]]
	private(set) var calls: [String] = []

	init(results: [String: [String]]) {
		self.results = results
	}

	func deviceJIDs(for jid: String) async throws -> [String] {
		calls.append(jid)
		return results[jid] ?? []
	}
}

private actor MockGroupMessageSendTransport: WhatsAppWebSocketTransport {
	private var sentFrames: [Data] = []
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

	func waitForSentNode(at index: Int) async throws -> BinaryNode {
		while sentFrames.count <= index {
			try await Task.sleep(for: .milliseconds(1))
		}

		var codec = NoiseFrameCodec()
		return try BinaryNodeDecoder().decode(codec.decode(sentFrames[index])[0])
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

private func groupMessageNode() -> BinaryNode {
	BinaryNode(
		tag: "group",
		attrs: [
			"id": "120363000000000000",
			"subject": "Swift Group",
			"addressing_mode": "lid"
		],
		content: .nodes([
			BinaryNode(tag: "participant", attrs: ["jid": "111@s.whatsapp.net"]),
			BinaryNode(tag: "participant", attrs: ["jid": "222@s.whatsapp.net"])
		])
	)
}

private func sampleGroupMessageCredentials() -> AuthenticationCredentials {
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
		me: WhatsAppUser(id: "999@s.whatsapp.net", lid: "999@lid"),
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true
	)
}
