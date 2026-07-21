import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client media message send")
struct WhatsAppClientMediaMessageSendTests {
	@Test("sends image messages after encrypting and uploading media")
	func sendsImageMessagesAfterEncryptingAndUploadingMedia() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0x55]))
		], callOrder: callOrder)
		let deviceResolver = StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"])
		let mediaUploader = StubWhatsAppMediaUploader(result: MediaUploadResult(
			mediaURL: "https://media.example/uploaded",
			directPath: "/v/t62.7118-24/direct-path",
			metaHMAC: "meta",
			timestamp: 1_700_000_001,
			fileID: 123
		))
		let mediaKey = try hexData("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: sessionPreparer,
			messageEncoder: MessageEncoder(randomByte: { 0x00 }),
			mediaUploader: mediaUploader,
			mediaKeyGenerator: StubMediaKeyGenerator(mediaKey: mediaKey),
			mediaKeyTimestamp: { 1_700_000_000 }
		)
		try await client.connect()

		let messageID = try await client.sendImageMessage(
			to: "123@s.whatsapp.net",
			imageData: Data("swift baileys media fixture".utf8),
			caption: "swift image",
			messageID: "3EB0IMAGE"
		)

		let expectedEncryptedFile = try hexData("3a3018e9b6b731f67593006398f95c50dc0d3938ce1c2652b64845c2c9eeb87b5ecae5e287aaeebc57b1")
		let expectedFileEncSHA256 = try hexData("00f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d03")
		let expectedFileSHA256 = try hexData("fe07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce")

		#expect(messageID == "3EB0IMAGE")
		#expect(await mediaUploader.calls == [
			MediaUploadCall(
				data: expectedEncryptedFile,
				fileEncSha256Base64: expectedFileEncSHA256.base64EncodedString(),
				mediaType: .image
			)
		])
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])
		#expect(await callOrder.values == ["sessions", "encrypt:123.0@s.whatsapp.net"])

		let encryptorCalls = await encryptor.calls
		let encodedMessage = encryptorCalls[0].data
		#expect(encodedMessage.last == 0x01)
		let protobufMessage = try Proto_Message(serializedBytes: encodedMessage.dropLast())
		#expect(protobufMessage.imageMessage.url == "https://media.example/uploaded")
		#expect(protobufMessage.imageMessage.directPath == "/v/t62.7118-24/direct-path")
		#expect(protobufMessage.imageMessage.mediaKey == mediaKey)
		#expect(protobufMessage.imageMessage.fileEncSha256 == expectedFileEncSHA256)
		#expect(protobufMessage.imageMessage.fileSha256 == expectedFileSHA256)
		#expect(protobufMessage.imageMessage.fileLength == UInt64(Data("swift baileys media fixture".utf8).count))
		#expect(protobufMessage.imageMessage.mediaKeyTimestamp == 1_700_000_000)
		#expect(protobufMessage.imageMessage.mimetype == "image/jpeg")
		#expect(protobufMessage.imageMessage.caption == "swift image")

		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0IMAGE")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
		#expect(stanza.firstChild(named: "participants")?.firstChild(named: "to")?.attrs["jid"] == "123.0@s.whatsapp.net")
	}
}

actor StubWhatsAppMediaUploader: WhatsAppMediaUploading {
	private let result: MediaUploadResult
	private(set) var calls: [MediaUploadCall] = []

	init(result: MediaUploadResult) {
		self.result = result
	}

	func upload(_ data: Data, fileEncSha256Base64: String, mediaType: MediaType) async throws -> MediaUploadResult {
		calls.append(MediaUploadCall(data: data, fileEncSha256Base64: fileEncSha256Base64, mediaType: mediaType))
		return result
	}
}

struct MediaUploadCall: Equatable, Sendable {
	let data: Data
	let fileEncSha256Base64: String
	let mediaType: MediaType
}

struct StubMediaKeyGenerator: MediaKeyGenerating {
	let mediaKey: Data

	func makeMediaKey() throws -> Data {
		mediaKey
	}
}
