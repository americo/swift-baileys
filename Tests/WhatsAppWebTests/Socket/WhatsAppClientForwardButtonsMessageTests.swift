import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client forward buttons messages")
struct WhatsAppClientForwardButtonsMessageTests {
	@Test("forwards received buttons messages through the encrypted send path")
	func forwardsReceivedButtonsMessagesThroughEncryptedSendPath() async throws {
		let message = try await forwardedButtonsMessage(ReceivedButtonsContent(
			contentText: "Choose an action",
			footerText: "Order #123",
			buttons: [
				ReceivedButtonContent(
					buttonID: "confirm",
					displayText: "Confirm",
					type: .response,
					nativeFlowInfo: nil
				),
				ReceivedButtonContent(
					buttonID: "shipping",
					displayText: "Open form",
					type: .nativeFlow,
					nativeFlowInfo: ReceivedButtonNativeFlowInfoContent(
						name: "single_select",
						paramsJSON: #"{"screen":"shipping"}"#
					)
				)
			],
			headerType: .text,
			header: .text("Order actions")
		))
		#expect(message.hasButtonsMessage)
		#expect(message.buttonsMessage.contentText == "Choose an action")
		#expect(message.buttonsMessage.footerText == "Order #123")
		#expect(message.buttonsMessage.headerType == .text)
		#expect(message.buttonsMessage.text == "Order actions")
		#expect(message.buttonsMessage.buttons.map { $0.buttonID } == ["confirm", "shipping"])
		#expect(message.buttonsMessage.buttons.map { $0.buttonText.displayText } == ["Confirm", "Open form"])
		#expect(message.buttonsMessage.buttons[1].type == .nativeFlow)
		#expect(message.buttonsMessage.buttons[1].nativeFlowInfo.name == "single_select")
		#expect(message.buttonsMessage.contextInfo.isForwarded)
		#expect(message.buttonsMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards received buttons media headers through the encrypted send path")
	func forwardsReceivedButtonsMediaHeadersThroughEncryptedSendPath() async throws {
		let imageMessage = try await forwardedButtonsMessage(ReceivedButtonsContent(
			contentText: "View image",
			footerText: nil,
			buttons: [button],
			headerType: .image,
			header: .image(ReceivedImageContent(
				url: "https://mmg.whatsapp.net/image.enc",
				directPath: "/image.enc",
				mediaKey: Data([0x01]),
				fileEncSHA256: Data([0x02]),
				fileSHA256: Data([0x03]),
				fileLength: 512,
				mediaKeyTimestamp: 1_700_000_001,
				mimetype: "image/jpeg",
				caption: "image header",
				jpegThumbnail: Data([0x04])
			))
		))
		#expect(imageMessage.buttonsMessage.headerType == .image)
		guard case .imageMessage(let imageHeader)? = imageMessage.buttonsMessage.header else {
			Issue.record("expected image buttons header")
			return
		}
		#expect(imageHeader.url == "https://mmg.whatsapp.net/image.enc")
		#expect(imageHeader.directPath == "/image.enc")
		#expect(imageHeader.mediaKey == Data([0x01]))
		#expect(imageHeader.fileEncSha256 == Data([0x02]))
		#expect(imageHeader.fileSha256 == Data([0x03]))
		#expect(imageHeader.fileLength == 512)
		#expect(imageHeader.mediaKeyTimestamp == 1_700_000_001)
		#expect(imageHeader.mimetype == "image/jpeg")
		#expect(imageHeader.caption == "image header")
		#expect(imageHeader.jpegThumbnail == Data([0x04]))

		let documentMessage = try await forwardedButtonsMessage(ReceivedButtonsContent(
			contentText: "Open document",
			footerText: nil,
			buttons: [button],
			headerType: .document,
			header: .document(ReceivedDocumentContent(
				url: "https://mmg.whatsapp.net/doc.enc",
				directPath: "/doc.enc",
				mediaKey: Data([0x05]),
				fileEncSHA256: Data([0x06]),
				fileSHA256: Data([0x07]),
				fileLength: 1_024,
				mediaKeyTimestamp: 1_700_000_002,
				mimetype: "application/pdf",
				fileName: "invoice.pdf",
				title: "Invoice",
				pageCount: 3
			))
		))
		#expect(documentMessage.buttonsMessage.headerType == .document)
		guard case .documentMessage(let documentHeader)? = documentMessage.buttonsMessage.header else {
			Issue.record("expected document buttons header")
			return
		}
		#expect(documentHeader.url == "https://mmg.whatsapp.net/doc.enc")
		#expect(documentHeader.directPath == "/doc.enc")
		#expect(documentHeader.mediaKey == Data([0x05]))
		#expect(documentHeader.fileEncSha256 == Data([0x06]))
		#expect(documentHeader.fileSha256 == Data([0x07]))
		#expect(documentHeader.fileLength == 1_024)
		#expect(documentHeader.mediaKeyTimestamp == 1_700_000_002)
		#expect(documentHeader.mimetype == "application/pdf")
		#expect(documentHeader.fileName == "invoice.pdf")
		#expect(documentHeader.title == "Invoice")
		#expect(documentHeader.pageCount == 3)

		let videoMessage = try await forwardedButtonsMessage(ReceivedButtonsContent(
			contentText: "Play video",
			footerText: nil,
			buttons: [button],
			headerType: .video,
			header: .video(ReceivedVideoContent(
				url: "https://mmg.whatsapp.net/video.enc",
				directPath: "/video.enc",
				mediaKey: Data([0x08]),
				fileEncSHA256: Data([0x09]),
				fileSHA256: Data([0x0a]),
				fileLength: 2_048,
				mediaKeyTimestamp: 1_700_000_003,
				mimetype: "video/mp4",
				caption: "video header",
				seconds: 12,
				width: 640,
				height: 480,
				isGIFPlayback: true,
				jpegThumbnail: Data([0x0b])
			))
		))
		#expect(videoMessage.buttonsMessage.headerType == .video)
		guard case .videoMessage(let videoHeader)? = videoMessage.buttonsMessage.header else {
			Issue.record("expected video buttons header")
			return
		}
		#expect(videoHeader.url == "https://mmg.whatsapp.net/video.enc")
		#expect(videoHeader.directPath == "/video.enc")
		#expect(videoHeader.mediaKey == Data([0x08]))
		#expect(videoHeader.fileEncSha256 == Data([0x09]))
		#expect(videoHeader.fileSha256 == Data([0x0a]))
		#expect(videoHeader.fileLength == 2_048)
		#expect(videoHeader.mediaKeyTimestamp == 1_700_000_003)
		#expect(videoHeader.mimetype == "video/mp4")
		#expect(videoHeader.caption == "video header")
		#expect(videoHeader.seconds == 12)
		#expect(videoHeader.width == 640)
		#expect(videoHeader.height == 480)
		#expect(videoHeader.gifPlayback)
		#expect(videoHeader.jpegThumbnail == Data([0x0b]))

		let locationMessage = try await forwardedButtonsMessage(ReceivedButtonsContent(
			contentText: "Open map",
			footerText: nil,
			buttons: [button],
			headerType: .location,
			header: .location(ReceivedLocationContent(
				latitude: -25.966,
				longitude: 32.583,
				name: "Maputo",
				address: "Av. 24 de Julho",
				url: "https://maps.example/location",
				accuracyInMeters: 12,
				comment: "meet here",
				jpegThumbnail: Data([0x0c])
			))
		))
		#expect(locationMessage.buttonsMessage.headerType == .location)
		guard case .locationMessage(let locationHeader)? = locationMessage.buttonsMessage.header else {
			Issue.record("expected location buttons header")
			return
		}
		#expect(locationHeader.degreesLatitude == -25.966)
		#expect(locationHeader.degreesLongitude == 32.583)
		#expect(locationHeader.name == "Maputo")
		#expect(locationHeader.address == "Av. 24 de Julho")
		#expect(locationHeader.url == "https://maps.example/location")
		#expect(locationHeader.accuracyInMeters == 12)
		#expect(locationHeader.comment == "meet here")
		#expect(locationHeader.jpegThumbnail == Data([0x0c]))
	}

	private var button: ReceivedButtonContent {
		ReceivedButtonContent(
			buttonID: "open",
			displayText: "Open",
			type: .response,
			nativeFlowInfo: nil
		)
	}

	private func forwardedButtonsMessage(_ content: ReceivedButtonsContent) async throws -> Proto_Message {
		let callOrder = MessageSendCallOrder()
		let encryptor = StubMessageSendEncryptor(
			results: [EncryptedMessage(type: "msg", ciphertext: Data([0x20]))],
			callOrder: callOrder
		)
		let client = WhatsAppClient(
			transportFactory: { _ in MockMessageSendWebSocketTransport() },
			messageEncryptor: encryptor,
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendForwardedMessage(
			to: "123@s.whatsapp.net",
			message: ReceivedMessage(
				id: "BUTTONS1",
				from: "456@s.whatsapp.net",
				timestamp: nil,
				content: .buttons(content),
				fromMe: false
			),
			messageID: "3EB0FORWARDEDBUTTONS"
		)

		let payload = await encryptor.calls[0].data.dropLast()
		return try Proto_Message(serializedBytes: payload)
	}
}
