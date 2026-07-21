import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client media send")
struct WhatsAppClientMediaSendTests {
	@Test("sends view once uploaded image messages")
	func sendsViewOnceUploadedImageMessages() async throws {
		let result = try await sendMediaMessage(
			mediaKeyHex: "a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf"
		) { client in
			try await client.sendImageMessage(
				to: "123@s.whatsapp.net",
				imageData: Data("swift image fixture".utf8),
				caption: "image caption",
				viewOnce: true,
				messageID: "3EB0VIEWONCEIMAGE"
			)
		}

		#expect(result.upload.mediaType == .image)
		#expect(result.messageID == "3EB0VIEWONCEIMAGE")
		#expect(result.message.hasViewOnceMessage)
		let image = result.message.viewOnceMessage.message.imageMessage
		#expect(image.mimetype == "image/jpeg")
		#expect(image.caption == "image caption")
		#expect(image.url == "https://media.example/uploaded")
		#expect(image.directPath == "/v/t62.7118-24/direct-path")
		#expect(image.mediaKey == result.mediaKey)
	}

	@Test("sends uploaded image messages with mention context")
	func sendsUploadedImageMessagesWithMentionContext() async throws {
		let result = try await sendMediaMessage(
			mediaKeyHex: "a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf"
		) { client in
			try await client.sendImageMessage(
				to: "123@s.whatsapp.net",
				imageData: Data("swift image fixture".utf8),
				caption: "@alice hello",
				mentions: ["111@s.whatsapp.net"],
				mentionAll: true,
				ephemeralExpiration: 86_400,
				messageID: "3EB0IMAGEMENTION"
			)
		}

		#expect(result.messageID == "3EB0IMAGEMENTION")
		#expect(result.message.hasImageMessage)
		#expect(result.message.imageMessage.caption == "@alice hello")
		#expect(result.message.imageMessage.contextInfo.mentionedJid == ["111@s.whatsapp.net"])
		#expect(result.message.imageMessage.contextInfo.nonJidMentions == 1)
		#expect(result.message.imageMessage.contextInfo.expiration == 86_400)
	}

	@Test("sends uploaded image messages with album parent association")
	func sendsUploadedImageMessagesWithAlbumParentAssociation() async throws {
		let parent = WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: true, id: "3EB0ALBUM")
		let result = try await sendMediaMessage(
			mediaKeyHex: "a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf"
		) { client in
			try await client.sendImageMessage(
				to: "123@s.whatsapp.net",
				imageData: Data("swift image fixture".utf8),
				caption: "album image",
				albumParentKey: parent,
				messageID: "3EB0ALBUMIMAGE"
			)
		}

		#expect(result.messageID == "3EB0ALBUMIMAGE")
		#expect(result.message.imageMessage.caption == "album image")
		let association = result.message.messageContextInfo.messageAssociation
		#expect(association.associationType == .mediaAlbum)
		#expect(association.parentMessageKey.remoteJid == "123@s.whatsapp.net")
		#expect(association.parentMessageKey.fromMe)
		#expect(association.parentMessageKey.id == "3EB0ALBUM")
	}

	@Test("sends uploaded document messages")
	func sendsUploadedDocumentMessages() async throws {
		let result = try await sendMediaMessage(
			mediaKeyHex: "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f"
		) { client in
			try await client.sendDocumentMessage(
				to: "123@s.whatsapp.net",
				documentData: Data("swift document fixture".utf8),
				document: OutgoingDocumentContent(
					mimetype: "application/pdf",
					fileName: "swift.pdf",
					title: "Swift PDF",
					pageCount: 3,
					caption: "document caption"
				),
				messageID: "3EB0DOCUMENT"
			)
		}

		#expect(result.upload.mediaType == .document)
		#expect(result.messageID == "3EB0DOCUMENT")
		#expect(result.message.hasDocumentMessage)
		#expect(result.message.documentMessage.mimetype == "application/pdf")
		#expect(result.message.documentMessage.fileName == "swift.pdf")
		#expect(result.message.documentMessage.title == "Swift PDF")
		#expect(result.message.documentMessage.pageCount == 3)
		#expect(result.message.documentMessage.caption == "document caption")
		#expect(result.message.documentMessage.url == "https://media.example/uploaded")
		#expect(result.message.documentMessage.directPath == "/v/t62.7118-24/direct-path")
		#expect(result.message.documentMessage.mediaKey == result.mediaKey)
	}

	@Test("sends uploaded document messages with mention context")
	func sendsUploadedDocumentMessagesWithMentionContext() async throws {
		let result = try await sendMediaMessage(
			mediaKeyHex: "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f"
		) { client in
			try await client.sendDocumentMessage(
				to: "123@s.whatsapp.net",
				documentData: Data("swift document fixture".utf8),
				document: OutgoingDocumentContent(
					mimetype: "application/pdf",
					fileName: "swift.pdf",
					caption: "@alice document"
				),
				mentions: ["111@s.whatsapp.net"],
				mentionAll: true,
				ephemeralExpiration: 86_400,
				messageID: "3EB0DOCUMENTMENTION"
			)
		}

		#expect(result.messageID == "3EB0DOCUMENTMENTION")
		#expect(result.message.hasDocumentMessage)
		#expect(result.message.documentMessage.caption == "@alice document")
		#expect(result.message.documentMessage.contextInfo.mentionedJid == ["111@s.whatsapp.net"])
		#expect(result.message.documentMessage.contextInfo.nonJidMentions == 1)
		#expect(result.message.documentMessage.contextInfo.expiration == 86_400)
	}

	@Test("sends uploaded audio messages")
	func sendsUploadedAudioMessages() async throws {
		let result = try await sendMediaMessage(
			mediaKeyHex: "404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f"
		) { client in
			try await client.sendAudioMessage(
				to: "123@s.whatsapp.net",
				audioData: Data("swift audio fixture".utf8),
				audio: OutgoingAudioContent(
					mimetype: "audio/ogg; codecs=opus",
					seconds: 12,
					isVoiceMessage: true,
					waveform: Data([0x01, 0x02, 0x03])
				),
				messageID: "3EB0AUDIO"
			)
		}

		#expect(result.upload.mediaType == .audio)
		#expect(result.messageID == "3EB0AUDIO")
		#expect(result.message.hasAudioMessage)
		#expect(result.message.audioMessage.mimetype == "audio/ogg; codecs=opus")
		#expect(result.message.audioMessage.seconds == 12)
		#expect(result.message.audioMessage.ptt == true)
		#expect(result.message.audioMessage.waveform == Data([0x01, 0x02, 0x03]))
		#expect(result.message.audioMessage.url == "https://media.example/uploaded")
		#expect(result.message.audioMessage.directPath == "/v/t62.7118-24/direct-path")
		#expect(result.message.audioMessage.mediaKey == result.mediaKey)
	}

	@Test("sends uploaded video messages")
	func sendsUploadedVideoMessages() async throws {
		let result = try await sendMediaMessage(
			mediaKeyHex: "606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f"
		) { client in
			try await client.sendVideoMessage(
				to: "123@s.whatsapp.net",
				videoData: Data("swift video fixture".utf8),
				video: OutgoingVideoContent(
					mimetype: "video/mp4",
					caption: "video caption",
					seconds: 5,
					width: 640,
					height: 360,
					isGIFPlayback: true,
					jpegThumbnail: Data([0x0a, 0x0b])
				),
				messageID: "3EB0VIDEO"
			)
		}

		#expect(result.upload.mediaType == .video)
		#expect(result.messageID == "3EB0VIDEO")
		#expect(result.message.hasVideoMessage)
		#expect(result.message.videoMessage.mimetype == "video/mp4")
		#expect(result.message.videoMessage.caption == "video caption")
		#expect(result.message.videoMessage.seconds == 5)
		#expect(result.message.videoMessage.width == 640)
		#expect(result.message.videoMessage.height == 360)
		#expect(result.message.videoMessage.gifPlayback == true)
		#expect(result.message.videoMessage.jpegThumbnail == Data([0x0a, 0x0b]))
		#expect(result.message.videoMessage.url == "https://media.example/uploaded")
		#expect(result.message.videoMessage.directPath == "/v/t62.7118-24/direct-path")
		#expect(result.message.videoMessage.mediaKey == result.mediaKey)
	}

	@Test("sends uploaded video messages with mention context")
	func sendsUploadedVideoMessagesWithMentionContext() async throws {
		let result = try await sendMediaMessage(
			mediaKeyHex: "606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f"
		) { client in
			try await client.sendVideoMessage(
				to: "123@s.whatsapp.net",
				videoData: Data("swift video fixture".utf8),
				video: OutgoingVideoContent(mimetype: "video/mp4", caption: "@alice video"),
				mentions: ["111@s.whatsapp.net"],
				mentionAll: true,
				ephemeralExpiration: 86_400,
				messageID: "3EB0VIDEOMENTION"
			)
		}

		#expect(result.messageID == "3EB0VIDEOMENTION")
		#expect(result.message.hasVideoMessage)
		#expect(result.message.videoMessage.caption == "@alice video")
		#expect(result.message.videoMessage.contextInfo.mentionedJid == ["111@s.whatsapp.net"])
		#expect(result.message.videoMessage.contextInfo.nonJidMentions == 1)
		#expect(result.message.videoMessage.contextInfo.expiration == 86_400)
	}

	@Test("sends uploaded video messages with album parent association")
	func sendsUploadedVideoMessagesWithAlbumParentAssociation() async throws {
		let parent = WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: true, id: "3EB0ALBUM")
		let result = try await sendMediaMessage(
			mediaKeyHex: "606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f"
		) { client in
			try await client.sendVideoMessage(
				to: "123@s.whatsapp.net",
				videoData: Data("swift video fixture".utf8),
				video: OutgoingVideoContent(mimetype: "video/mp4", caption: "album video"),
				albumParentKey: parent,
				messageID: "3EB0ALBUMVIDEO"
			)
		}

		#expect(result.messageID == "3EB0ALBUMVIDEO")
		#expect(result.message.videoMessage.caption == "album video")
		let association = result.message.messageContextInfo.messageAssociation
		#expect(association.associationType == .mediaAlbum)
		#expect(association.parentMessageKey.id == "3EB0ALBUM")
	}

	@Test("sends uploaded PTV messages")
	func sendsUploadedPTVMessages() async throws {
		let result = try await sendMediaMessage(
			mediaKeyHex: "707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f"
		) { client in
			try await client.sendPTVMessage(
				to: "123@s.whatsapp.net",
				videoData: Data("swift ptv fixture".utf8),
				video: OutgoingVideoContent(
					mimetype: "video/mp4",
					seconds: 4,
					width: 320,
					height: 320,
					jpegThumbnail: Data([0x0e, 0x0f])
				),
				messageID: "3EB0PTV"
			)
		}

		#expect(result.upload.mediaType == .video)
		#expect(result.messageID == "3EB0PTV")
		#expect(result.message.hasPtvMessage)
		#expect(result.message.hasVideoMessage == false)
		#expect(result.message.ptvMessage.mimetype == "video/mp4")
		#expect(result.message.ptvMessage.seconds == 4)
		#expect(result.message.ptvMessage.width == 320)
		#expect(result.message.ptvMessage.height == 320)
		#expect(result.message.ptvMessage.jpegThumbnail == Data([0x0e, 0x0f]))
		#expect(result.message.ptvMessage.url == "https://media.example/uploaded")
		#expect(result.message.ptvMessage.directPath == "/v/t62.7118-24/direct-path")
		#expect(result.message.ptvMessage.mediaKey == result.mediaKey)
	}

	@Test("sends uploaded sticker messages")
	func sendsUploadedStickerMessages() async throws {
		let result = try await sendMediaMessage(
			mediaKeyHex: "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f"
		) { client in
			try await client.sendStickerMessage(
				to: "123@s.whatsapp.net",
				stickerData: Data("swift sticker fixture".utf8),
				sticker: OutgoingStickerContent(
					mimetype: "image/webp",
					width: 512,
					height: 512,
					isAnimated: false,
					pngThumbnail: Data([0x0c, 0x0d])
				),
				messageID: "3EB0STICKER"
			)
		}

		#expect(result.upload.mediaType == .sticker)
		#expect(result.messageID == "3EB0STICKER")
		#expect(result.message.hasStickerMessage)
		#expect(result.message.stickerMessage.mimetype == "image/webp")
		#expect(result.message.stickerMessage.width == 512)
		#expect(result.message.stickerMessage.height == 512)
		#expect(result.message.stickerMessage.isAnimated == false)
		#expect(result.message.stickerMessage.pngThumbnail == Data([0x0c, 0x0d]))
		#expect(result.message.stickerMessage.url == "https://media.example/uploaded")
		#expect(result.message.stickerMessage.directPath == "/v/t62.7118-24/direct-path")
		#expect(result.message.stickerMessage.mediaKey == result.mediaKey)
	}
}

private func sendMediaMessage(
	mediaKeyHex: String,
	send: (WhatsAppClient) async throws -> String
) async throws -> SentMediaMessage {
	let transport = MockMessageSendWebSocketTransport()
	let callOrder = MessageSendCallOrder()
	let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
	let encryptor = StubMessageSendEncryptor(results: [
		EncryptedMessage(type: "msg", ciphertext: Data([0x01]))
	], callOrder: callOrder)
	let deviceResolver = StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"])
	let mediaUploader = StubWhatsAppMediaUploader(result: MediaUploadResult(
		mediaURL: "https://media.example/uploaded",
		directPath: "/v/t62.7118-24/direct-path",
		metaHMAC: "meta",
		timestamp: 1_700_000_001,
		fileID: 123
	))
	let mediaKey = try Data(hexString: mediaKeyHex)
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

	let messageID = try await send(client)

	#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
	#expect(await sessionPreparer.calls == [
		SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
	])
	#expect(await callOrder.values == ["sessions", "encrypt:123.0@s.whatsapp.net"])

	let upload = try #require(await mediaUploader.calls.first)
	let encryptorCall = try #require(await encryptor.calls.first)
	let message = try Proto_Message(serializedBytes: encryptorCall.data.dropLast())
	return SentMediaMessage(messageID: messageID, message: message, upload: upload, mediaKey: mediaKey)
}

private struct SentMediaMessage: Sendable {
	let messageID: String
	let message: Proto_Message
	let upload: MediaUploadCall
	let mediaKey: Data
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw MessageSendMediaTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}
}

private enum MessageSendMediaTestError: Error {
	case invalidHex
}
