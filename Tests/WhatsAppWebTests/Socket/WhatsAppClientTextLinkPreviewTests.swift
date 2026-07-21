import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client text link previews")
struct WhatsAppClientTextLinkPreviewTests {
	@Test("generates link preview metadata through configured resolver")
	func generatesLinkPreviewMetadataThroughConfiguredResolver() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x11]))],
			callOrder: callOrder
		)
		let resolver = StubLinkPreviewResolver(result: OutgoingLinkPreviewContent(
			matchedText: "https://example.com",
			title: "Generated title",
			description: "Generated description"
		))
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		await client.configureLinkPreviewResolver(resolver)
		try await client.connect()

		_ = try await client.sendTextMessage(
			to: "123@s.whatsapp.net",
			text: "Read https://example.com now",
			messageID: "3EB0AUTOLINK"
		)

		let requestedURLs = await resolver.requestedURLs
		#expect(requestedURLs == ["https://example.com"])
		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.extendedTextMessage.text == "Read https://example.com now")
		#expect(message.extendedTextMessage.matchedText == "https://example.com")
		#expect(message.extendedTextMessage.title == "Generated title")
		#expect(message.extendedTextMessage.description_p == "Generated description")
	}

	@Test("does not call resolver when link preview is explicit")
	func doesNotCallResolverWhenLinkPreviewIsExplicit() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x10]))],
			callOrder: callOrder
		)
		let resolver = StubLinkPreviewResolver(result: OutgoingLinkPreviewContent(
			matchedText: "https://generated.example",
			title: "Generated"
		))
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		await client.configureLinkPreviewResolver(resolver)
		try await client.connect()

		_ = try await client.sendTextMessage(
			to: "123@s.whatsapp.net",
			text: "Read https://example.com now",
			linkPreview: OutgoingLinkPreviewContent(matchedText: "https://manual.example", title: "Manual"),
			messageID: "3EB0MANUALLINK"
		)

		let requestedURLs = await resolver.requestedURLs
		#expect(requestedURLs.isEmpty)
		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.extendedTextMessage.matchedText == "https://manual.example")
		#expect(message.extendedTextMessage.title == "Manual")
	}

	@Test("encodes link preview metadata in outbound text messages")
	func encodesLinkPreviewMetadataInOutboundTextMessages() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x12]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendTextMessage(
			to: "123@s.whatsapp.net",
			content: OutgoingTextContent(
				text: "Read https://example.com now",
				linkPreview: OutgoingLinkPreviewContent(
					matchedText: "https://example.com",
					title: "Example title",
					description: "Example description",
					jpegThumbnail: Data([0x01, 0x02, 0x03])
				)
			),
			messageID: "3EB0LINK"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.extendedTextMessage.text == "Read https://example.com now")
		#expect(message.extendedTextMessage.matchedText == "https://example.com")
		#expect(message.extendedTextMessage.title == "Example title")
		#expect(message.extendedTextMessage.description_p == "Example description")
		#expect(message.extendedTextMessage.jpegThumbnail == Data([0x01, 0x02, 0x03]))
	}

	@Test("encodes text presentation metadata in outbound text messages")
	func encodesTextPresentationMetadataInOutboundTextMessages() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x13]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendTextMessage(
			to: "123@s.whatsapp.net",
			text: "styled text",
			backgroundARGB: 0xff112233,
			font: .fbScript,
			messageID: "3EB0STYLE"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		let message = try Proto_Message(serializedBytes: payload)
		#expect(message.extendedTextMessage.text == "styled text")
		#expect(message.extendedTextMessage.backgroundArgb == 0xff112233)
		#expect(message.extendedTextMessage.font == .fbScript)
	}
}

private actor StubLinkPreviewResolver: LinkPreviewResolving {
	let result: OutgoingLinkPreviewContent?
	private(set) var requestedURLs: [String] = []

	init(result: OutgoingLinkPreviewContent?) {
		self.result = result
	}

	func linkPreview(for url: String) async throws -> OutgoingLinkPreviewContent? {
		requestedURLs.append(url)
		return result
	}
}
