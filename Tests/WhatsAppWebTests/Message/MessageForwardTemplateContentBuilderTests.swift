import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Message forward template content builder")
struct MessageForwardTemplateContentBuilderTests {
	@Test("forwards template text through extracted content")
	func forwardsTemplateTextThroughExtractedContent() throws {
		var hydrated = Proto_Message.TemplateMessage.HydratedFourRowTemplate()
		hydrated.hydratedContentText = "Template text"
		var template = Proto_Message.TemplateMessage()
		template.hydratedTemplate = hydrated
		var source = Proto_Message()
		source.templateMessage = template

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasExtendedTextMessage)
		#expect(message.extendedTextMessage.text == "Template text")
		#expect(message.extendedTextMessage.contextInfo.isForwarded)
		#expect(message.extendedTextMessage.contextInfo.forwardingScore == 1)
	}

	@Test("forwards template media through extracted content")
	func forwardsTemplateMediaThroughExtractedContent() throws {
		var image = Proto_Message.ImageMessage()
		image.url = "https://mmg.whatsapp.net/template-image.enc"
		image.directPath = "/template-image.enc"
		image.mediaKey = Data([0x01])
		image.fileEncSha256 = Data([0x02])
		image.fileSha256 = Data([0x03])
		var fourRow = Proto_Message.TemplateMessage.FourRowTemplate()
		fourRow.imageMessage = image
		var template = Proto_Message.TemplateMessage()
		template.fourRowTemplate = fourRow
		var source = Proto_Message()
		source.templateMessage = template

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasImageMessage)
		#expect(message.imageMessage.url == "https://mmg.whatsapp.net/template-image.enc")
		#expect(message.imageMessage.directPath == "/template-image.enc")
		#expect(message.imageMessage.mediaKey == Data([0x01]))
		#expect(message.imageMessage.fileEncSha256 == Data([0x02]))
		#expect(message.imageMessage.fileSha256 == Data([0x03]))
		#expect(message.imageMessage.contextInfo.isForwarded)
		#expect(message.imageMessage.contextInfo.forwardingScore == 1)
	}
}
