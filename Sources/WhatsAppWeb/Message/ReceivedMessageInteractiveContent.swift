import Foundation

public enum ReceivedInteractiveHeaderMediaContent: Equatable, Sendable {
	case document(ReceivedDocumentContent)
	case image(ReceivedImageContent)
	case jpegThumbnail(Data)
	case video(ReceivedVideoContent)
	case location(ReceivedLocationContent)
	case product(ReceivedProductContent)
}

public struct ReceivedInteractiveHeaderContent: Equatable, Sendable {
	public let title: String?
	public let subtitle: String?
	public let hasMediaAttachment: Bool?
	public let media: ReceivedInteractiveHeaderMediaContent?

	public init(
		title: String?,
		subtitle: String?,
		hasMediaAttachment: Bool?,
		media: ReceivedInteractiveHeaderMediaContent?
	) {
		self.title = title
		self.subtitle = subtitle
		self.hasMediaAttachment = hasMediaAttachment
		self.media = media
	}
}

public enum ReceivedInteractiveFooterMediaContent: Equatable, Sendable {
	case audio(ReceivedAudioContent)
}

public struct ReceivedInteractiveFooterContent: Equatable, Sendable {
	public let text: String?
	public let hasMediaAttachment: Bool?
	public let media: ReceivedInteractiveFooterMediaContent?

	public init(text: String?, hasMediaAttachment: Bool?, media: ReceivedInteractiveFooterMediaContent?) {
		self.text = text
		self.hasMediaAttachment = hasMediaAttachment
		self.media = media
	}
}

public struct ReceivedInteractiveBodyContent: Equatable, Sendable {
	public let text: String?

	public init(text: String?) {
		self.text = text
	}
}

public enum ReceivedInteractiveShopSurface: Equatable, Sendable {
	case unknown
	case facebook
	case instagram
	case wa
	case unrecognized(Int)
}

public struct ReceivedInteractiveShopContent: Equatable, Sendable {
	public let id: String?
	public let surface: ReceivedInteractiveShopSurface?
	public let messageVersion: Int32?

	public init(id: String?, surface: ReceivedInteractiveShopSurface?, messageVersion: Int32?) {
		self.id = id
		self.surface = surface
		self.messageVersion = messageVersion
	}
}

public struct ReceivedInteractiveCollectionContent: Equatable, Sendable {
	public let bizJID: String?
	public let id: String?
	public let messageVersion: Int32?

	public init(bizJID: String?, id: String?, messageVersion: Int32?) {
		self.bizJID = bizJID
		self.id = id
		self.messageVersion = messageVersion
	}
}

public struct ReceivedInteractiveNativeFlowButtonContent: Equatable, Sendable {
	public let name: String?
	public let buttonParamsJSON: String?

	public init(name: String?, buttonParamsJSON: String?) {
		self.name = name
		self.buttonParamsJSON = buttonParamsJSON
	}
}

public struct ReceivedInteractiveNativeFlowContent: Equatable, Sendable {
	public let buttons: [ReceivedInteractiveNativeFlowButtonContent]
	public let messageParamsJSON: String?
	public let messageVersion: Int32?

	public init(
		buttons: [ReceivedInteractiveNativeFlowButtonContent],
		messageParamsJSON: String?,
		messageVersion: Int32?
	) {
		self.buttons = buttons
		self.messageParamsJSON = messageParamsJSON
		self.messageVersion = messageVersion
	}
}

public enum ReceivedInteractiveCarouselCardType: Equatable, Sendable {
	case unknown
	case hscrollCards
	case albumImage
	case unrecognized(Int)
}

public struct ReceivedInteractiveCarouselContent: Equatable, Sendable {
	public let cards: [ReceivedInteractiveContent]
	public let messageVersion: Int32?
	public let cardType: ReceivedInteractiveCarouselCardType?

	public init(cards: [ReceivedInteractiveContent], messageVersion: Int32?, cardType: ReceivedInteractiveCarouselCardType?) {
		self.cards = cards
		self.messageVersion = messageVersion
		self.cardType = cardType
	}
}

public indirect enum ReceivedInteractiveMessageVariant: Equatable, Sendable {
	case shop(ReceivedInteractiveShopContent)
	case collection(ReceivedInteractiveCollectionContent)
	case nativeFlow(ReceivedInteractiveNativeFlowContent)
	case carousel(ReceivedInteractiveCarouselContent)
}

public struct ReceivedInteractiveContent: Equatable, Sendable {
	public let header: ReceivedInteractiveHeaderContent?
	public let body: ReceivedInteractiveBodyContent?
	public let footer: ReceivedInteractiveFooterContent?
	public let message: ReceivedInteractiveMessageVariant?

	public init(
		header: ReceivedInteractiveHeaderContent?,
		body: ReceivedInteractiveBodyContent?,
		footer: ReceivedInteractiveFooterContent?,
		message: ReceivedInteractiveMessageVariant?
	) {
		self.header = header
		self.body = body
		self.footer = footer
		self.message = message
	}
}
