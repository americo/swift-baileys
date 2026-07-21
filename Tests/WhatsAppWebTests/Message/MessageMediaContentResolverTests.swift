import Testing
@testable import WhatsAppWeb

@Suite("Message media content resolver")
struct MessageMediaContentResolverTests {
	@Test("returns direct media content")
	func returnsDirectMediaContent() throws {
		var image = Proto_Message.ImageMessage()
		image.url = "https://mmg.whatsapp.net/image"
		var message = Proto_Message()
		message.imageMessage = image

		#expect(try MessageMediaContentResolver.assertMediaContent(message) == .image(image))
	}

	@Test("extracts media content from buttons messages")
	func extractsMediaContentFromButtonsMessages() throws {
		var video = Proto_Message.VideoMessage()
		video.url = "https://mmg.whatsapp.net/video"
		var buttons = Proto_Message.ButtonsMessage()
		buttons.videoMessage = video
		var message = Proto_Message()
		message.buttonsMessage = buttons

		#expect(try MessageMediaContentResolver.assertMediaContent(message) == .video(video))
	}

	@Test("extracts media content from template messages")
	func extractsMediaContentFromTemplateMessages() throws {
		var document = Proto_Message.DocumentMessage()
		document.url = "https://mmg.whatsapp.net/document"
		var hydrated = Proto_Message.TemplateMessage.HydratedFourRowTemplate()
		hydrated.documentMessage = document
		var template = Proto_Message.TemplateMessage()
		template.hydratedFourRowTemplate = hydrated
		var message = Proto_Message()
		message.templateMessage = template

		#expect(try MessageMediaContentResolver.assertMediaContent(message) == .document(document))
	}

	@Test("throws for non media messages")
	func throwsForNonMediaMessages() {
		let message = MessageContentBuilder.text("plain")

		#expect(throws: MessageMediaContentError.notMediaMessage) {
			try MessageMediaContentResolver.assertMediaContent(message)
		}
	}
}
