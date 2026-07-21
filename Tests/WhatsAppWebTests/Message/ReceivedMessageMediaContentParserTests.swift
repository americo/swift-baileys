import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message media content parser")
struct ReceivedMessageMediaContentParserTests {
	@Test("parses image media into a downloadable descriptor")
	func parsesImageMediaIntoDownloadableDescriptor() throws {
		let mediaKey = try hexData("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
		let fileEncSHA256 = try hexData("00f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d03")
		let fileSHA256 = try hexData("fe07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce")
		let message = MessageContentBuilder.uploadedImage(UploadedImageContent(
			url: "https://mmg.whatsapp.net/o1/v/t62.7118-24/example",
			directPath: "/v/t62.7118-24/example.enc?ccb=11-4&oh=01",
			mediaKey: mediaKey,
			fileEncSha256: fileEncSHA256,
			fileSha256: fileSHA256,
			fileLength: 27,
			mediaKeyTimestamp: 1_700_000_000,
			mimetype: "image/jpeg",
			caption: "swift image"
		))

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .image(ReceivedImageContent(
			url: "https://mmg.whatsapp.net/o1/v/t62.7118-24/example",
			directPath: "/v/t62.7118-24/example.enc?ccb=11-4&oh=01",
			mediaKey: mediaKey,
			fileEncSHA256: fileEncSHA256,
			fileSHA256: fileSHA256,
			fileLength: 27,
			mediaKeyTimestamp: 1_700_000_000,
			mimetype: "image/jpeg",
			caption: "swift image",
			jpegThumbnail: nil
		)))
		#expect(try content.mediaDownloadRequest()?.url.absoluteString == "https://mmg.whatsapp.net/v/t62.7118-24/example.enc?ccb=11-4&oh=01")
	}

	@Test("parses document media into a downloadable descriptor")
	func parsesDocumentMediaIntoDownloadableDescriptor() throws {
		let mediaKey = try hexData("101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f")
		let fileEncSHA256 = try hexData("a0f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d")
		let fileSHA256 = try hexData("be07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce")
		var document = Proto_Message.DocumentMessage()
		document.url = "https://mmg.whatsapp.net/o1/v/t62.7119-24/document"
		document.directPath = "/v/t62.7119-24/document.enc?ccb=11-4&oh=01"
		document.mediaKey = mediaKey
		document.fileEncSha256 = fileEncSHA256
		document.fileSha256 = fileSHA256
		document.fileLength = 4096
		document.mediaKeyTimestamp = 1_700_000_123
		document.mimetype = "application/pdf"
		document.fileName = "invoice.pdf"
		document.title = "Invoice"
		document.pageCount = 3
		var message = Proto_Message()
		message.documentMessage = document

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .document(ReceivedDocumentContent(
			url: "https://mmg.whatsapp.net/o1/v/t62.7119-24/document",
			directPath: "/v/t62.7119-24/document.enc?ccb=11-4&oh=01",
			mediaKey: mediaKey,
			fileEncSHA256: fileEncSHA256,
			fileSHA256: fileSHA256,
			fileLength: 4096,
			mediaKeyTimestamp: 1_700_000_123,
			mimetype: "application/pdf",
			fileName: "invoice.pdf",
			title: "Invoice",
			pageCount: 3
		)))
		#expect(try content.mediaDownloadRequest()?.mediaType == .document)
	}

	@Test("parses audio media into a downloadable descriptor")
	func parsesAudioMediaIntoDownloadableDescriptor() throws {
		let mediaKey = try hexData("202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f")
		let fileEncSHA256 = try hexData("c0f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d")
		let fileSHA256 = try hexData("de07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce")
		var audio = Proto_Message.AudioMessage()
		audio.url = "https://mmg.whatsapp.net/o1/v/t62.7117-24/audio"
		audio.directPath = "/v/t62.7117-24/audio.enc?ccb=11-4&oh=01"
		audio.mediaKey = mediaKey
		audio.fileEncSha256 = fileEncSHA256
		audio.fileSha256 = fileSHA256
		audio.fileLength = 2048
		audio.mediaKeyTimestamp = 1_700_000_456
		audio.mimetype = "audio/ogg; codecs=opus"
		audio.seconds = 12
		audio.ptt = true
		audio.waveform = Data([0x01, 0x02, 0x03])
		var message = Proto_Message()
		message.audioMessage = audio

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .audio(ReceivedAudioContent(
			url: "https://mmg.whatsapp.net/o1/v/t62.7117-24/audio",
			directPath: "/v/t62.7117-24/audio.enc?ccb=11-4&oh=01",
			mediaKey: mediaKey,
			fileEncSHA256: fileEncSHA256,
			fileSHA256: fileSHA256,
			fileLength: 2048,
			mediaKeyTimestamp: 1_700_000_456,
			mimetype: "audio/ogg; codecs=opus",
			seconds: 12,
			isVoiceMessage: true,
			waveform: Data([0x01, 0x02, 0x03])
		)))
		#expect(try content.mediaDownloadRequest()?.mediaType == .audio)
	}

	@Test("parses video media into a downloadable descriptor")
	func parsesVideoMediaIntoDownloadableDescriptor() throws {
		let mediaKey = try hexData("303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f")
		let fileEncSHA256 = try hexData("e0f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d")
		let fileSHA256 = try hexData("fa07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce")
		var video = Proto_Message.VideoMessage()
		video.url = "https://mmg.whatsapp.net/o1/v/t62.7161-24/video"
		video.directPath = "/v/t62.7161-24/video.enc?ccb=11-4&oh=01"
		video.mediaKey = mediaKey
		video.fileEncSha256 = fileEncSHA256
		video.fileSha256 = fileSHA256
		video.fileLength = 8192
		video.mediaKeyTimestamp = 1_700_000_789
		video.mimetype = "video/mp4"
		video.caption = "swift video"
		video.seconds = 42
		video.width = 1280
		video.height = 720
		video.gifPlayback = true
		video.jpegThumbnail = Data([0x04, 0x05, 0x06])
		var message = Proto_Message()
		message.videoMessage = video

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .video(ReceivedVideoContent(
			url: "https://mmg.whatsapp.net/o1/v/t62.7161-24/video",
			directPath: "/v/t62.7161-24/video.enc?ccb=11-4&oh=01",
			mediaKey: mediaKey,
			fileEncSHA256: fileEncSHA256,
			fileSHA256: fileSHA256,
			fileLength: 8192,
			mediaKeyTimestamp: 1_700_000_789,
			mimetype: "video/mp4",
			caption: "swift video",
			seconds: 42,
			width: 1280,
			height: 720,
			isGIFPlayback: true,
			jpegThumbnail: Data([0x04, 0x05, 0x06])
		)))
		#expect(try content.mediaDownloadRequest()?.mediaType == .video)
	}

	@Test("parses ptv messages as video media")
	func parsesPtvMessagesAsVideoMedia() throws {
		let mediaKey = try hexData("505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f")
		let fileEncSHA256 = try hexData("a1f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d")
		let fileSHA256 = try hexData("b207adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce")
		var video = Proto_Message.VideoMessage()
		video.url = "https://mmg.whatsapp.net/o1/v/t62.7161-24/ptv"
		video.directPath = "/v/t62.7161-24/ptv.enc?ccb=11-4&oh=01"
		video.mediaKey = mediaKey
		video.fileEncSha256 = fileEncSHA256
		video.fileSha256 = fileSHA256
		video.fileLength = 4096
		video.mediaKeyTimestamp = 1_700_111_222
		video.mimetype = "video/mp4"
		video.seconds = 8
		video.width = 480
		video.height = 480
		var message = Proto_Message()
		message.ptvMessage = video

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .video(ReceivedVideoContent(
			url: "https://mmg.whatsapp.net/o1/v/t62.7161-24/ptv",
			directPath: "/v/t62.7161-24/ptv.enc?ccb=11-4&oh=01",
			mediaKey: mediaKey,
			fileEncSHA256: fileEncSHA256,
			fileSHA256: fileSHA256,
			fileLength: 4096,
			mediaKeyTimestamp: 1_700_111_222,
			mimetype: "video/mp4",
			caption: nil,
			seconds: 8,
			width: 480,
			height: 480,
			isGIFPlayback: false,
			jpegThumbnail: nil
		)))
		#expect(try content.mediaDownloadRequest()?.mediaType == .video)
	}

	@Test("parses sticker media into a downloadable descriptor")
	func parsesStickerMediaIntoDownloadableDescriptor() throws {
		let mediaKey = try hexData("404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f")
		let fileEncSHA256 = try hexData("10f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d")
		let fileSHA256 = try hexData("2e07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce")
		var sticker = Proto_Message.StickerMessage()
		sticker.url = "https://mmg.whatsapp.net/o1/v/t62.7161-24/sticker"
		sticker.directPath = "/v/t62.7161-24/sticker.enc?ccb=11-4&oh=01"
		sticker.mediaKey = mediaKey
		sticker.fileEncSha256 = fileEncSHA256
		sticker.fileSha256 = fileSHA256
		sticker.fileLength = 1024
		sticker.mediaKeyTimestamp = 1_700_000_987
		sticker.mimetype = "image/webp"
		sticker.width = 512
		sticker.height = 512
		sticker.isAnimated = true
		sticker.isAvatar = true
		sticker.isAiSticker = true
		sticker.isLottie = true
		sticker.pngThumbnail = Data([0x07, 0x08, 0x09])
		var message = Proto_Message()
		message.stickerMessage = sticker

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .sticker(ReceivedStickerContent(
			url: "https://mmg.whatsapp.net/o1/v/t62.7161-24/sticker",
			directPath: "/v/t62.7161-24/sticker.enc?ccb=11-4&oh=01",
			mediaKey: mediaKey,
			fileEncSHA256: fileEncSHA256,
			fileSHA256: fileSHA256,
			fileLength: 1024,
			mediaKeyTimestamp: 1_700_000_987,
			mimetype: "image/webp",
			width: 512,
			height: 512,
			isAnimated: true,
			isAvatar: true,
			isAISticker: true,
			isLottie: true,
			pngThumbnail: Data([0x07, 0x08, 0x09])
		)))
		#expect(try content.mediaDownloadRequest()?.mediaType == .sticker)
	}
}
