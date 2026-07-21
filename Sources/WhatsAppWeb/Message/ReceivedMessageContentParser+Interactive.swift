extension ReceivedMessageContentParser {
	static func interactiveContent(_ interactive: Proto_Message.InteractiveMessage) -> ReceivedInteractiveContent {
		ReceivedInteractiveContent(
			header: interactive.hasHeader ? interactiveHeader(interactive.header) : nil,
			body: interactive.hasBody ? interactiveBody(interactive.body) : nil,
			footer: interactive.hasFooter ? interactiveFooter(interactive.footer) : nil,
			message: interactiveVariant(interactive.interactiveMessage)
		)
	}

	static func interactiveBody(_ body: Proto_Message.InteractiveMessage.Body) -> ReceivedInteractiveBodyContent {
		ReceivedInteractiveBodyContent(text: body.hasText ? body.text : nil)
	}

	static func interactiveHeader(
		_ header: Proto_Message.InteractiveMessage.Header
	) -> ReceivedInteractiveHeaderContent {
		ReceivedInteractiveHeaderContent(
			title: header.hasTitle ? header.title : nil,
			subtitle: header.hasSubtitle ? header.subtitle : nil,
			hasMediaAttachment: header.hasHasMediaAttachment_p ? header.hasMediaAttachment_p : nil,
			media: interactiveHeaderMedia(header.media)
		)
	}

	static func interactiveHeaderMedia(
		_ media: Proto_Message.InteractiveMessage.Header.OneOf_Media?
	) -> ReceivedInteractiveHeaderMediaContent? {
		switch media {
		case .documentMessage(let document):
			.document(documentContent(document))
		case .imageMessage(let image):
			.image(imageContent(image))
		case .jpegThumbnail(let thumbnail):
			.jpegThumbnail(thumbnail)
		case .videoMessage(let video):
			.video(videoContent(video))
		case .locationMessage(let location):
			.location(locationContent(location))
		case .productMessage(let product):
			.product(productContent(product))
		case nil:
			nil
		}
	}

	static func interactiveFooter(
		_ footer: Proto_Message.InteractiveMessage.Footer
	) -> ReceivedInteractiveFooterContent {
		ReceivedInteractiveFooterContent(
			text: footer.hasText ? footer.text : nil,
			hasMediaAttachment: footer.hasHasMediaAttachment_p ? footer.hasMediaAttachment_p : nil,
			media: interactiveFooterMedia(footer.media)
		)
	}

	static func interactiveFooterMedia(
		_ media: Proto_Message.InteractiveMessage.Footer.OneOf_Media?
	) -> ReceivedInteractiveFooterMediaContent? {
		switch media {
		case .audioMessage(let audio):
			.audio(audioContent(audio))
		case nil:
			nil
		}
	}

	static func interactiveVariant(
		_ variant: Proto_Message.InteractiveMessage.OneOf_InteractiveMessage?
	) -> ReceivedInteractiveMessageVariant? {
		switch variant {
		case .shopStorefrontMessage(let shop):
			.shop(interactiveShop(shop))
		case .collectionMessage(let collection):
			.collection(interactiveCollection(collection))
		case .nativeFlowMessage(let nativeFlow):
			.nativeFlow(interactiveNativeFlow(nativeFlow))
		case .carouselMessage(let carousel):
			.carousel(interactiveCarousel(carousel))
		case nil:
			nil
		}
	}

	static func interactiveShop(_ shop: Proto_Message.InteractiveMessage.ShopMessage) -> ReceivedInteractiveShopContent {
		ReceivedInteractiveShopContent(
			id: shop.hasID ? shop.id : nil,
			surface: shop.hasSurface ? interactiveShopSurface(shop.surface) : nil,
			messageVersion: shop.hasMessageVersion ? shop.messageVersion : nil
		)
	}

	static func interactiveShopSurface(
		_ surface: Proto_Message.InteractiveMessage.ShopMessage.Surface
	) -> ReceivedInteractiveShopSurface {
		switch surface {
		case .unknownSurface:
			.unknown
		case .fb:
			.facebook
		case .ig:
			.instagram
		case .wa:
			.wa
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	static func interactiveCollection(
		_ collection: Proto_Message.InteractiveMessage.CollectionMessage
	) -> ReceivedInteractiveCollectionContent {
		ReceivedInteractiveCollectionContent(
			bizJID: collection.hasBizJid ? collection.bizJid : nil,
			id: collection.hasID ? collection.id : nil,
			messageVersion: collection.hasMessageVersion ? collection.messageVersion : nil
		)
	}

	static func interactiveNativeFlow(
		_ nativeFlow: Proto_Message.InteractiveMessage.NativeFlowMessage
	) -> ReceivedInteractiveNativeFlowContent {
		ReceivedInteractiveNativeFlowContent(
			buttons: nativeFlow.buttons.map(interactiveNativeFlowButton),
			messageParamsJSON: nativeFlow.hasMessageParamsJson ? nativeFlow.messageParamsJson : nil,
			messageVersion: nativeFlow.hasMessageVersion ? nativeFlow.messageVersion : nil
		)
	}

	static func interactiveNativeFlowButton(
		_ button: Proto_Message.InteractiveMessage.NativeFlowMessage.NativeFlowButton
	) -> ReceivedInteractiveNativeFlowButtonContent {
		ReceivedInteractiveNativeFlowButtonContent(
			name: button.hasName ? button.name : nil,
			buttonParamsJSON: button.hasButtonParamsJson ? button.buttonParamsJson : nil
		)
	}

	static func interactiveCarousel(
		_ carousel: Proto_Message.InteractiveMessage.CarouselMessage
	) -> ReceivedInteractiveCarouselContent {
		ReceivedInteractiveCarouselContent(
			cards: carousel.cards.map(interactiveContent),
			messageVersion: carousel.hasMessageVersion ? carousel.messageVersion : nil,
			cardType: carousel.hasCarouselCardType ? interactiveCarouselCardType(carousel.carouselCardType) : nil
		)
	}

	static func interactiveCarouselCardType(
		_ cardType: Proto_Message.InteractiveMessage.CarouselMessage.CarouselCardType
	) -> ReceivedInteractiveCarouselCardType {
		switch cardType {
		case .unknown:
			.unknown
		case .hscrollCards:
			.hscrollCards
		case .albumImage:
			.albumImage
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}
}
