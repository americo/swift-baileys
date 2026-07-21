import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Incoming message decryptor")
struct IncomingMessageDecryptorTests {
	@Test("decrypts direct encrypted message nodes")
	func decryptsDirectEncryptedMessageNodes() async throws {
		let signalDecryptor = StubSignalMessageDecryptor(result: try MessageEncoder(randomByte: { 0x00 }).encode(
			MessageContentBuilder.text("hello decrypted")
		))
		let decryptor = SignalIncomingMessageDecryptor(signalDecryptor: signalDecryptor)
		let node = BinaryNode(
			tag: "message",
			attrs: ["from": "123@s.whatsapp.net"],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0x01, 0x02, 0x03])))
			])
		)

		let message = try #require(try await decryptor.decryptIncomingMessage(from: node))

		#expect(message.extendedTextMessage.text == "hello decrypted")
		#expect(await signalDecryptor.calls == [
			SignalMessageDecryptCall(jid: "123@s.whatsapp.net", type: "msg", ciphertext: Data([0x01, 0x02, 0x03]))
		])
	}

	@Test("decrypts direct message nodes with mapped LID sessions")
	func decryptsDirectMessageNodesWithMappedLIDSessions() async throws {
		let signalDecryptor = StubSignalMessageDecryptor(result: try MessageEncoder(randomByte: { 0x00 }).encode(
			MessageContentBuilder.text("hello mapped lid")
		))
		let decryptor = SignalIncomingMessageDecryptor(
			signalDecryptor: signalDecryptor,
			localJIDProvider: { nil },
			decryptionJIDResolver: { jid in
				#expect(jid == "123@s.whatsapp.net")
				return "123@lid"
			}
		)
		let node = BinaryNode(
			tag: "message",
			attrs: ["from": "123@s.whatsapp.net"],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0x01, 0x02, 0x03])))
			])
		)

		let message = try #require(try await decryptor.decryptIncomingMessage(from: node))

		#expect(message.extendedTextMessage.text == "hello mapped lid")
		#expect(await signalDecryptor.calls == [
			SignalMessageDecryptCall(jid: "123@lid", type: "msg", ciphertext: Data([0x01, 0x02, 0x03]))
		])
	}

	@Test("decodes plaintext message nodes without Signal")
	func decodesPlaintextMessageNodesWithoutSignal() async throws {
		let signalDecryptor = StubSignalMessageDecryptor(result: Data())
		let decryptor = SignalIncomingMessageDecryptor(signalDecryptor: signalDecryptor)
		let plaintext = try MessageContentBuilder.text("hello plaintext").serializedData()
		let node = BinaryNode(
			tag: "message",
			attrs: ["from": "123@s.whatsapp.net"],
			content: .nodes([
				BinaryNode(tag: "plaintext", content: .data(plaintext))
			])
		)

		let message = try #require(try await decryptor.decryptIncomingMessage(from: node))

		#expect(message.extendedTextMessage.text == "hello plaintext")
		#expect(await signalDecryptor.calls.isEmpty)
	}

	@Test("decrypts group sender key message nodes")
	func decryptsGroupSenderKeyMessageNodes() async throws {
		let signalDecryptor = StubSignalMessageDecryptor(result: try MessageEncoder(randomByte: { 0x00 }).encode(
			MessageContentBuilder.text("hello group")
		))
		let decryptor = SignalIncomingMessageDecryptor(signalDecryptor: signalDecryptor)
		let node = BinaryNode(
			tag: "message",
			attrs: [
				"from": "111-222@g.us",
				"participant": "123@s.whatsapp.net"
			],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "skmsg"], content: .data(Data([0x04, 0x05, 0x06])))
			])
		)

		let message = try #require(try await decryptor.decryptIncomingMessage(from: node))

		#expect(message.extendedTextMessage.text == "hello group")
		#expect(await signalDecryptor.groupCalls == [
			SignalGroupMessageDecryptCall(
				group: "111-222@g.us",
				authorJID: "123@s.whatsapp.net",
				ciphertext: Data([0x04, 0x05, 0x06])
			)
		])
		#expect(await signalDecryptor.calls.isEmpty)
	}

	@Test("rejects direct encrypted message nodes with empty ciphertext before Signal")
	func rejectsDirectEncryptedMessageNodesWithEmptyCiphertextBeforeSignal() async throws {
		let signalDecryptor = StubSignalMessageDecryptor(result: Data())
		let decryptor = SignalIncomingMessageDecryptor(signalDecryptor: signalDecryptor)
		let node = BinaryNode(
			tag: "message",
			attrs: ["from": "123@s.whatsapp.net"],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data()))
			])
		)

		await #expect(throws: SignalIncomingMessageDecryptorError.emptyCiphertext) {
			_ = try await decryptor.decryptIncomingMessage(from: node)
		}
		#expect(await signalDecryptor.calls.isEmpty)
	}

	@Test("rejects group encrypted message nodes with empty ciphertext before Signal")
	func rejectsGroupEncryptedMessageNodesWithEmptyCiphertextBeforeSignal() async throws {
		let signalDecryptor = StubSignalMessageDecryptor(result: Data())
		let decryptor = SignalIncomingMessageDecryptor(signalDecryptor: signalDecryptor)
		let node = BinaryNode(
			tag: "message",
			attrs: [
				"from": "111-222@g.us",
				"participant": "123@s.whatsapp.net"
			],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "skmsg"], content: .data(Data()))
			])
		)

		await #expect(throws: SignalIncomingMessageDecryptorError.emptyCiphertext) {
			_ = try await decryptor.decryptIncomingMessage(from: node)
		}
		#expect(await signalDecryptor.groupCalls.isEmpty)
	}

	@Test("unwraps device sent message envelopes")
	func unwrapsDeviceSentMessageEnvelopes() async throws {
		var deviceSent = Proto_Message.DeviceSentMessage()
		deviceSent.destinationJid = "123@s.whatsapp.net"
		deviceSent.message = MessageContentBuilder.text("hello from linked device")
		var envelope = Proto_Message()
		envelope.deviceSentMessage = deviceSent
		let signalDecryptor = StubSignalMessageDecryptor(result: try MessageEncoder(randomByte: { 0x00 }).encode(envelope))
		let decryptor = SignalIncomingMessageDecryptor(signalDecryptor: signalDecryptor)
		let node = BinaryNode(
			tag: "message",
			attrs: ["from": "123@s.whatsapp.net"],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0x07, 0x08, 0x09])))
			])
		)

		let message = try #require(try await decryptor.decryptIncomingMessage(from: node))

		#expect(!message.hasDeviceSentMessage)
		#expect(message.extendedTextMessage.text == "hello from linked device")
	}

	@Test("processes sender key distribution messages after decrypting")
	func processesSenderKeyDistributionMessagesAfterDecrypting() async throws {
		var distribution = Proto_Message.SenderKeyDistributionMessage()
		distribution.groupID = "111-222@g.us"
		distribution.axolotlSenderKeyDistributionMessage = Data([0xaa, 0xbb])
		var payload = MessageContentBuilder.text("hello with sender key")
		payload.senderKeyDistributionMessage = distribution
		let signalDecryptor = StubSignalMessageDecryptor(result: try MessageEncoder(randomByte: { 0x00 }).encode(payload))
		let decryptor = SignalIncomingMessageDecryptor(signalDecryptor: signalDecryptor)
		let node = BinaryNode(
			tag: "message",
			attrs: [
				"from": "111-222@g.us",
				"participant": "123@s.whatsapp.net"
			],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0x0a, 0x0b])))
			])
		)

		let message = try #require(try await decryptor.decryptIncomingMessage(from: node))

		#expect(message.extendedTextMessage.text == "hello with sender key")
		#expect(await signalDecryptor.senderKeyDistributionCalls == [
			SenderKeyDistributionCall(
				authorJID: "123@s.whatsapp.net",
				groupJID: "111-222@g.us",
				senderKeyDistributionData: Data([0xaa, 0xbb]),
				messageData: try distribution.serializedData()
			)
		])
	}

	@Test("processes fast ratchet sender key distribution messages after decrypting")
	func processesFastRatchetSenderKeyDistributionMessagesAfterDecrypting() async throws {
		var distribution = Proto_Message.SenderKeyDistributionMessage()
		distribution.groupID = "111-222@g.us"
		distribution.axolotlSenderKeyDistributionMessage = Data([0xcc, 0xdd])
		var payload = MessageContentBuilder.text("hello with fast ratchet sender key")
		payload.fastRatchetKeySenderKeyDistributionMessage = distribution
		let signalDecryptor = StubSignalMessageDecryptor(result: try MessageEncoder(randomByte: { 0x00 }).encode(payload))
		let decryptor = SignalIncomingMessageDecryptor(signalDecryptor: signalDecryptor)
		let node = BinaryNode(
			tag: "message",
			attrs: [
				"from": "111-222@g.us",
				"participant": "123@s.whatsapp.net"
			],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(Data([0x0c, 0x0d])))
			])
		)

		let message = try #require(try await decryptor.decryptIncomingMessage(from: node))

		#expect(message.extendedTextMessage.text == "hello with fast ratchet sender key")
		#expect(await signalDecryptor.senderKeyDistributionCalls == [
			SenderKeyDistributionCall(
				authorJID: "123@s.whatsapp.net",
				groupJID: "111-222@g.us",
				senderKeyDistributionData: Data([0xcc, 0xdd]),
				messageData: try distribution.serializedData()
			)
		])
	}
}

private actor StubSignalMessageDecryptor: SignalMessageDecrypting {
	private let result: Data
	private(set) var calls: [SignalMessageDecryptCall] = []
	private(set) var groupCalls: [SignalGroupMessageDecryptCall] = []
	private(set) var senderKeyDistributionCalls: [SenderKeyDistributionCall] = []

	init(result: Data) {
		self.result = result
	}

	func decryptMessage(jid: String, type: String, ciphertext: Data) async throws -> Data {
		calls.append(SignalMessageDecryptCall(jid: jid, type: type, ciphertext: ciphertext))
		return result
	}

	func decryptGroupMessage(group: String, authorJID: String, ciphertext: Data) async throws -> Data {
		groupCalls.append(SignalGroupMessageDecryptCall(group: group, authorJID: authorJID, ciphertext: ciphertext))
		return result
	}

	func processSenderKeyDistributionMessage(authorJID: String, messageData: Data) async throws {
		senderKeyDistributionCalls.append(SenderKeyDistributionCall(
			authorJID: authorJID,
			groupJID: nil,
			senderKeyDistributionData: nil,
			messageData: messageData
		))
	}

	func processSenderKeyDistributionMessage(_ request: SenderKeyDistributionMessageRequest) async throws {
		senderKeyDistributionCalls.append(SenderKeyDistributionCall(
			authorJID: request.authorJID,
			groupJID: request.groupJID,
			senderKeyDistributionData: request.senderKeyDistributionData,
			messageData: request.messageData
		))
	}
}

private struct SignalMessageDecryptCall: Equatable, Sendable {
	let jid: String
	let type: String
	let ciphertext: Data
}

private struct SignalGroupMessageDecryptCall: Equatable, Sendable {
	let group: String
	let authorJID: String
	let ciphertext: Data
}

private struct SenderKeyDistributionCall: Equatable, Sendable {
	let authorJID: String
	let groupJID: String?
	let senderKeyDistributionData: Data?
	let messageData: Data
}
