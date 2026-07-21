import Testing
@testable import WhatsAppWeb

@Suite("Message content extractor")
struct MessageContentExtractorTests {
	@Test("extracts media header from buttons messages")
	func extractsMediaHeaderFromButtonsMessages() {
		var image = Proto_Message.ImageMessage()
		image.url = "https://mmg.whatsapp.net/header"
		var buttons = Proto_Message.ButtonsMessage()
		buttons.contentText = "Fallback text"
		buttons.imageMessage = image
		var message = Proto_Message()
		message.buttonsMessage = buttons

		let extracted = MessageContentNormalizer.extractedContent(message)

		#expect(extracted.hasImageMessage)
		#expect(extracted.imageMessage.url == "https://mmg.whatsapp.net/header")
	}

	@Test("extracts content text from buttons messages without media")
	func extractsContentTextFromButtonsMessagesWithoutMedia() {
		var buttons = Proto_Message.ButtonsMessage()
		buttons.contentText = "Choose an action"
		var message = Proto_Message()
		message.buttonsMessage = buttons

		#expect(MessageContentNormalizer.extractedContent(message).conversation == "Choose an action")
	}

	@Test("extracts hydrated template text")
	func extractsHydratedTemplateText() {
		var hydrated = Proto_Message.TemplateMessage.HydratedFourRowTemplate()
		hydrated.hydratedContentText = "Hydrated text"
		var template = Proto_Message.TemplateMessage()
		template.hydratedTemplate = hydrated
		var message = Proto_Message()
		message.templateMessage = template

		#expect(MessageContentNormalizer.extractedContent(message).conversation == "Hydrated text")
	}

	@Test("extracts four row template media")
	func extractsFourRowTemplateMedia() {
		var location = Proto_Message.LocationMessage()
		location.name = "Maputo"
		var fourRow = Proto_Message.TemplateMessage.FourRowTemplate()
		fourRow.locationMessage = location
		var template = Proto_Message.TemplateMessage()
		template.fourRowTemplate = fourRow
		var message = Proto_Message()
		message.templateMessage = template

		let extracted = MessageContentNormalizer.extractedContent(message)

		#expect(extracted.hasLocationMessage)
		#expect(extracted.locationMessage.name == "Maputo")
	}

	@Test("normalizes wrappers before extracting template content")
	func normalizesWrappersBeforeExtractingTemplateContent() {
		var hydrated = Proto_Message.TemplateMessage.HydratedFourRowTemplate()
		hydrated.hydratedContentText = "Wrapped template"
		var template = Proto_Message.TemplateMessage()
		template.hydratedFourRowTemplate = hydrated
		var inner = Proto_Message()
		inner.templateMessage = template
		let message = futureProofMessage(inner) { $0.ephemeralMessage = $1 }

		#expect(MessageContentNormalizer.extractedContent(message).conversation == "Wrapped template")
	}
}
