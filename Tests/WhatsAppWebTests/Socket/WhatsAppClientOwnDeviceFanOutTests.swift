import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client own-device fan-out")
struct WhatsAppClientOwnDeviceFanOutTests {
	private static let me = WhatsAppUser(id: "999:21@s.whatsapp.net", lid: "888@lid")

	@Test("a phone-number chat also targets our other devices, not this one")
	func phoneNumberChatIncludesOwnDevices() async {
		let devices = await fanOut(to: "123@s.whatsapp.net", recipients: ["123@s.whatsapp.net"], own: [
			"999@s.whatsapp.net": ["999@s.whatsapp.net", "999:21@s.whatsapp.net", "999:5@s.whatsapp.net"]
		])

		#expect(devices == ["123@s.whatsapp.net", "999@s.whatsapp.net", "999:5@s.whatsapp.net"])
	}

	@Test("a LID chat addresses our devices by LID, and the bare LID is the phone")
	func lidChatUsesOwnLID() async {
		let devices = await fanOut(to: "123@lid", recipients: ["123@lid"], own: [
			"888@lid": ["888@lid", "888:21@lid"]
		])

		#expect(devices == ["123@lid", "888@lid"])
	}

	@Test("a message to ourselves reaches our other devices but not this one")
	func selfChatSkipsThisDevice() async {
		let devices = await fanOut(
			to: "999@s.whatsapp.net",
			recipients: ["999@s.whatsapp.net", "999:21@s.whatsapp.net"],
			own: [:]
		)

		#expect(devices == ["999@s.whatsapp.net"])
	}

	@Test("a failed lookup of our devices keeps the recipient's")
	func ownDeviceFailureStillSends() async {
		let devices = await fanOut(to: "123@s.whatsapp.net", recipients: ["123@s.whatsapp.net"], own: [:])

		#expect(devices == ["123@s.whatsapp.net"])
	}

	@Test("a recipient without devices does not become a send only to ourselves")
	func recipientWithoutDevicesStaysEmpty() async {
		let devices = await fanOut(to: "123@s.whatsapp.net", recipients: [], own: [
			"999@s.whatsapp.net": ["999@s.whatsapp.net"]
		])

		#expect(devices.isEmpty)
	}

	@Test("peer messages stay with their recipient")
	func peerMessagesSkipOwnDevices() async {
		let devices = await fanOut(
			to: "999@s.whatsapp.net",
			recipients: ["999@s.whatsapp.net"],
			own: ["999@s.whatsapp.net": ["999@s.whatsapp.net", "999:5@s.whatsapp.net"]],
			attributes: ["category": "peer"]
		)

		#expect(devices == ["999@s.whatsapp.net"])
	}

	@Test("the phone gets the sender copy envelope when our LID has no device part")
	func bareLIDPhoneIsWrapped() async throws {
		let encryptor = FanOutRecordingEncryptor()
		let builder = MessageRelayBuilder(encoder: MessageEncoder(randomByte: { 0x00 }), encryptor: encryptor)

		_ = try await builder.buildDirectMessageStanza(
			to: "123@lid",
			messageID: "3EB0BARELID",
			message: MessageContentBuilder.text("hello"),
			recipientDeviceJIDs: ["123@lid", "888@lid"],
			localJID: Self.me.id,
			localLID: Self.me.lid
		)

		let phone = try Proto_Message(serializedBytes: try #require(await encryptor.payloads["888@lid"]).dropLast())
		#expect(phone.deviceSentMessage.destinationJid == "123@lid")
		let recipient = try Proto_Message(serializedBytes: try #require(await encryptor.payloads["123@lid"]).dropLast())
		#expect(!recipient.hasDeviceSentMessage)
	}

	@Test("a retry for our own phone carries the sender copy envelope")
	func retryForOwnPhoneIsWrapped() async throws {
		let encryptor = FanOutRecordingEncryptor()
		let builder = MessageRelayBuilder(encoder: MessageEncoder(randomByte: { 0x00 }), encryptor: encryptor)

		let stanza = try await builder.buildRetryMessageStanza(
			to: "123@s.whatsapp.net",
			messageID: "3EB0RETRYOWN",
			message: MessageContentBuilder.text("hello"),
			participantJID: "999@s.whatsapp.net",
			retryCount: 1,
			localUserJID: Self.me.id,
			localUserLID: Self.me.lid
		)

		#expect(stanza.attrs["recipient"] == "123@s.whatsapp.net")
		let payload = try #require(await encryptor.payloads["999@s.whatsapp.net"])
		let message = try Proto_Message(serializedBytes: payload.dropLast())
		#expect(message.deviceSentMessage.destinationJid == "123@s.whatsapp.net")
	}

	private func fanOut(
		to destination: String,
		recipients: [String],
		own: [String: [String]],
		attributes: [String: String] = [:]
	) async -> [String] {
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: sampleMessageSendCredentials(me: Self.me),
				keys: InMemorySignalKeyStore(storage: [:])
			),
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: FanOutRecordingEncryptor(),
			messageDeviceResolver: PerUserDeviceResolver(devices: own),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: MessageSendCallOrder()),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)

		return await client.directFanOutDeviceJIDs(
			to: destination,
			recipientDeviceJIDs: recipients,
			additionalAttributes: attributes
		)
	}
}

private struct PerUserDeviceResolver: MessageDeviceResolving {
	let devices: [String: [String]]

	func deviceJIDs(for jid: String) async throws -> [String] {
		guard let found = devices[jid] else {
			throw MessageDeviceResolverError.invalidUSyncResponse
		}

		return found
	}
}

private actor FanOutRecordingEncryptor: MessageEncrypting {
	private(set) var payloads: [String: Data] = [:]

	func encryptMessage(jid: String, data: Data) async throws -> EncryptedMessage {
		payloads[jid] = data
		return EncryptedMessage(type: "msg", ciphertext: Data([0x01]))
	}
}
