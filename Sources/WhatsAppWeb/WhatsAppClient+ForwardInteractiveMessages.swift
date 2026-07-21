import Foundation

enum ForwardInteractiveMessageMapper {
	static func message(from content: ReceivedInteractiveContent) -> Proto_Message {
		let interactive = interactive(from: content)
		var message = Proto_Message()
		message.interactiveMessage = interactive
		return message
	}

	private static func interactive(from content: ReceivedInteractiveContent) -> Proto_Message.InteractiveMessage {
		var message = Proto_Message.InteractiveMessage()
		if let header = content.header {
			message.header = interactiveHeader(from: header)
		}
		if let body = content.body {
			message.body = interactiveBody(from: body)
		}
		if let footer = content.footer {
			message.footer = interactiveFooter(from: footer)
		}
		if let variant = content.message {
			switch variant {
			case .shop(let shop):
				message.shopStorefrontMessage = interactiveShop(from: shop)
			case .collection(let collection):
				message.collectionMessage = interactiveCollection(from: collection)
			case .nativeFlow(let nativeFlow):
				message.nativeFlowMessage = interactiveNativeFlow(from: nativeFlow)
			case .carousel(let carousel):
				message.carouselMessage = interactiveCarousel(from: carousel)
			}
		}
		return message
	}

	private static func interactiveHeader(
		from content: ReceivedInteractiveHeaderContent
	) -> Proto_Message.InteractiveMessage.Header {
		var header = Proto_Message.InteractiveMessage.Header()
		if let title = content.title {
			header.title = title
		}
		if let subtitle = content.subtitle {
			header.subtitle = subtitle
		}
		if let hasMediaAttachment = content.hasMediaAttachment {
			header.hasMediaAttachment_p = hasMediaAttachment
		}
		if let media = content.media {
			switch media {
			case .document(let document):
				header.documentMessage = ForwardMediaMessageMapper.document(from: document)
			case .image(let image):
				header.imageMessage = ForwardMediaMessageMapper.image(from: image)
			case .jpegThumbnail(let thumbnail):
				header.jpegThumbnail = thumbnail
			case .video(let video):
				header.videoMessage = ForwardMediaMessageMapper.video(from: video)
			case .location(let location):
				header.locationMessage = ForwardMediaMessageMapper.location(from: location)
			case .product(let product):
				header.productMessage = ForwardProductMessageMapper.product(from: product)
			}
		}
		return header
	}

	private static func interactiveBody(
		from content: ReceivedInteractiveBodyContent
	) -> Proto_Message.InteractiveMessage.Body {
		var body = Proto_Message.InteractiveMessage.Body()
		if let text = content.text {
			body.text = text
		}
		return body
	}

	private static func interactiveFooter(
		from content: ReceivedInteractiveFooterContent
	) -> Proto_Message.InteractiveMessage.Footer {
		var footer = Proto_Message.InteractiveMessage.Footer()
		if let text = content.text {
			footer.text = text
		}
		if let hasMediaAttachment = content.hasMediaAttachment {
			footer.hasMediaAttachment_p = hasMediaAttachment
		}
		if let media = content.media {
			switch media {
			case .audio(let audio):
				footer.audioMessage = ForwardMediaMessageMapper.audio(from: audio)
			}
		}
		return footer
	}

	private static func interactiveShop(
		from content: ReceivedInteractiveShopContent
	) -> Proto_Message.InteractiveMessage.ShopMessage {
		var shop = Proto_Message.InteractiveMessage.ShopMessage()
		if let id = content.id {
			shop.id = id
		}
		if let surface = content.surface {
			shop.surface = interactiveShopSurface(from: surface)
		}
		if let messageVersion = content.messageVersion {
			shop.messageVersion = messageVersion
		}
		return shop
	}

	private static func interactiveShopSurface(
		from surface: ReceivedInteractiveShopSurface
	) -> Proto_Message.InteractiveMessage.ShopMessage.Surface {
		switch surface {
		case .unknown:
			.unknownSurface
		case .facebook:
			.fb
		case .instagram:
			.ig
		case .wa:
			.wa
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}

	private static func interactiveCollection(
		from content: ReceivedInteractiveCollectionContent
	) -> Proto_Message.InteractiveMessage.CollectionMessage {
		var collection = Proto_Message.InteractiveMessage.CollectionMessage()
		if let bizJID = content.bizJID {
			collection.bizJid = bizJID
		}
		if let id = content.id {
			collection.id = id
		}
		if let messageVersion = content.messageVersion {
			collection.messageVersion = messageVersion
		}
		return collection
	}

	private static func interactiveNativeFlow(
		from content: ReceivedInteractiveNativeFlowContent
	) -> Proto_Message.InteractiveMessage.NativeFlowMessage {
		var nativeFlow = Proto_Message.InteractiveMessage.NativeFlowMessage()
		nativeFlow.buttons = content.buttons.map(interactiveNativeFlowButton)
		if let messageParamsJSON = content.messageParamsJSON {
			nativeFlow.messageParamsJson = messageParamsJSON
		}
		if let messageVersion = content.messageVersion {
			nativeFlow.messageVersion = messageVersion
		}
		return nativeFlow
	}

	private static func interactiveNativeFlowButton(
		from content: ReceivedInteractiveNativeFlowButtonContent
	) -> Proto_Message.InteractiveMessage.NativeFlowMessage.NativeFlowButton {
		var button = Proto_Message.InteractiveMessage.NativeFlowMessage.NativeFlowButton()
		if let name = content.name {
			button.name = name
		}
		if let buttonParamsJSON = content.buttonParamsJSON {
			button.buttonParamsJson = buttonParamsJSON
		}
		return button
	}

	private static func interactiveCarousel(
		from content: ReceivedInteractiveCarouselContent
	) -> Proto_Message.InteractiveMessage.CarouselMessage {
		var carousel = Proto_Message.InteractiveMessage.CarouselMessage()
		carousel.cards = content.cards.map(interactive)
		if let messageVersion = content.messageVersion {
			carousel.messageVersion = messageVersion
		}
		if let cardType = content.cardType {
			carousel.carouselCardType = interactiveCarouselCardType(from: cardType)
		}
		return carousel
	}

	private static func interactiveCarouselCardType(
		from cardType: ReceivedInteractiveCarouselCardType
	) -> Proto_Message.InteractiveMessage.CarouselMessage.CarouselCardType {
		switch cardType {
		case .unknown:
			.unknown
		case .hscrollCards:
			.hscrollCards
		case .albumImage:
			.albumImage
		case .unrecognized(let value):
			.UNRECOGNIZED(value)
		}
	}
}
