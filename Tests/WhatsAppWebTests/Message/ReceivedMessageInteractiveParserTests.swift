import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message interactive parser")
struct ReceivedMessageInteractiveParserTests {
	@Test("parses native flow interactive messages")
	func parsesNativeFlowInteractiveMessages() throws {
		var header = Proto_Message.InteractiveMessage.Header()
		header.title = "Checkout"
		header.subtitle = "Choose shipping"
		header.hasMediaAttachment_p = true
		header.jpegThumbnail = Data([0x01, 0x02])
		var body = Proto_Message.InteractiveMessage.Body()
		body.text = "Complete the form"
		var footer = Proto_Message.InteractiveMessage.Footer()
		footer.text = "Secure checkout"
		footer.hasMediaAttachment_p = false
		var button = Proto_Message.InteractiveMessage.NativeFlowMessage.NativeFlowButton()
		button.name = "single_select"
		button.buttonParamsJson = #"{"field":"shipping"}"#
		var nativeFlow = Proto_Message.InteractiveMessage.NativeFlowMessage()
		nativeFlow.buttons = [button]
		nativeFlow.messageParamsJson = #"{"screen":"checkout"}"#
		nativeFlow.messageVersion = 2
		var interactive = Proto_Message.InteractiveMessage()
		interactive.header = header
		interactive.body = body
		interactive.footer = footer
		interactive.nativeFlowMessage = nativeFlow
		var message = Proto_Message()
		message.interactiveMessage = interactive

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .interactive(ReceivedInteractiveContent(
			header: ReceivedInteractiveHeaderContent(
				title: "Checkout",
				subtitle: "Choose shipping",
				hasMediaAttachment: true,
				media: .jpegThumbnail(Data([0x01, 0x02]))
			),
			body: ReceivedInteractiveBodyContent(text: "Complete the form"),
			footer: ReceivedInteractiveFooterContent(
				text: "Secure checkout",
				hasMediaAttachment: false,
				media: nil
			),
			message: .nativeFlow(ReceivedInteractiveNativeFlowContent(
				buttons: [
					ReceivedInteractiveNativeFlowButtonContent(
						name: "single_select",
						buttonParamsJSON: #"{"field":"shipping"}"#
					)
				],
				messageParamsJSON: #"{"screen":"checkout"}"#,
				messageVersion: 2
			))
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses shop and collection interactive messages")
	func parsesShopAndCollectionInteractiveMessages() throws {
		var shop = Proto_Message.InteractiveMessage.ShopMessage()
		shop.id = "catalog-1"
		shop.surface = .wa
		shop.messageVersion = 1
		var shopMessage = Proto_Message.InteractiveMessage()
		shopMessage.shopStorefrontMessage = shop
		var collection = Proto_Message.InteractiveMessage.CollectionMessage()
		collection.bizJid = "258840000100@s.whatsapp.net"
		collection.id = "collection-1"
		collection.messageVersion = 3
		var collectionMessage = Proto_Message.InteractiveMessage()
		collectionMessage.collectionMessage = collection

		var firstMessage = Proto_Message()
		firstMessage.interactiveMessage = shopMessage
		var secondMessage = Proto_Message()
		secondMessage.interactiveMessage = collectionMessage

		let firstContent = try #require(ReceivedMessageContentParser.parse(firstMessage))
		let secondContent = try #require(ReceivedMessageContentParser.parse(secondMessage))

		#expect(firstContent == .interactive(ReceivedInteractiveContent(
			header: nil,
			body: nil,
			footer: nil,
			message: .shop(ReceivedInteractiveShopContent(
				id: "catalog-1",
				surface: .wa,
				messageVersion: 1
			))
		)))
		#expect(secondContent == .interactive(ReceivedInteractiveContent(
			header: nil,
			body: nil,
			footer: nil,
			message: .collection(ReceivedInteractiveCollectionContent(
				bizJID: "258840000100@s.whatsapp.net",
				id: "collection-1",
				messageVersion: 3
			))
		)))
	}

	@Test("parses carousel interactive messages recursively")
	func parsesCarouselInteractiveMessagesRecursively() throws {
		var cardBody = Proto_Message.InteractiveMessage.Body()
		cardBody.text = "Card body"
		var cardButton = Proto_Message.InteractiveMessage.NativeFlowMessage.NativeFlowButton()
		cardButton.name = "cta_url"
		cardButton.buttonParamsJson = #"{"url":"https://example.com"}"#
		var cardNativeFlow = Proto_Message.InteractiveMessage.NativeFlowMessage()
		cardNativeFlow.buttons = [cardButton]
		var card = Proto_Message.InteractiveMessage()
		card.body = cardBody
		card.nativeFlowMessage = cardNativeFlow
		var carousel = Proto_Message.InteractiveMessage.CarouselMessage()
		carousel.cards = [card]
		carousel.messageVersion = 4
		carousel.carouselCardType = .hscrollCards
		var interactive = Proto_Message.InteractiveMessage()
		interactive.carouselMessage = carousel
		var message = Proto_Message()
		message.interactiveMessage = interactive

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .interactive(ReceivedInteractiveContent(
			header: nil,
			body: nil,
			footer: nil,
			message: .carousel(ReceivedInteractiveCarouselContent(
				cards: [
					ReceivedInteractiveContent(
						header: nil,
						body: ReceivedInteractiveBodyContent(text: "Card body"),
						footer: nil,
						message: .nativeFlow(ReceivedInteractiveNativeFlowContent(
							buttons: [
								ReceivedInteractiveNativeFlowButtonContent(
									name: "cta_url",
									buttonParamsJSON: #"{"url":"https://example.com"}"#
								)
							],
							messageParamsJSON: nil,
							messageVersion: nil
						))
					)
				],
				messageVersion: 4,
				cardType: .hscrollCards
			))
		)))
	}
}
