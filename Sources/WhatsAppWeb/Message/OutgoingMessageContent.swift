import Foundation

public struct MessageReactionTarget: Equatable, Sendable {
	public let chatJID: String
	public let messageID: String
	public let fromMe: Bool
	public let participantJID: String?

	public init(chatJID: String, messageID: String, fromMe: Bool, participantJID: String? = nil) {
		self.chatJID = chatJID
		self.messageID = messageID
		self.fromMe = fromMe
		self.participantJID = participantJID
	}
}

public struct EventCreationMessageTarget: Equatable, Sendable {
	public let chatJID: String
	public let messageID: String
	public let fromMe: Bool
	public let participantJID: String?

	public init(chatJID: String, messageID: String, fromMe: Bool, participantJID: String? = nil) {
		self.chatJID = chatJID
		self.messageID = messageID
		self.fromMe = fromMe
		self.participantJID = participantJID
	}
}

public struct OutgoingQuotedTextContent: Equatable, Sendable {
	public let chatJID: String
	public let messageID: String
	public let participantJID: String
	public let text: String

	public init(chatJID: String, messageID: String, participantJID: String, text: String) {
		self.chatJID = chatJID
		self.messageID = messageID
		self.participantJID = participantJID
		self.text = text
	}
}

public struct OutgoingLinkPreviewThumbnailContent: Equatable, Sendable {
	public let directPath: String
	public let mediaKey: Data
	public let mediaKeyTimestamp: Int64
	public let width: UInt32?
	public let height: UInt32?
	public let fileSha256: Data?
	public let fileEncSha256: Data?

	public init(
		directPath: String,
		mediaKey: Data,
		mediaKeyTimestamp: Int64,
		width: UInt32? = nil,
		height: UInt32? = nil,
		fileSha256: Data? = nil,
		fileEncSha256: Data? = nil
	) {
		self.directPath = directPath
		self.mediaKey = mediaKey
		self.mediaKeyTimestamp = mediaKeyTimestamp
		self.width = width
		self.height = height
		self.fileSha256 = fileSha256
		self.fileEncSha256 = fileEncSha256
	}
}

public struct OutgoingLinkPreviewContent: Equatable, Sendable {
	public let matchedText: String
	public let title: String
	public let description: String?
	public let jpegThumbnail: Data?
	public let thumbnail: OutgoingLinkPreviewThumbnailContent?

	public init(
		matchedText: String,
		title: String,
		description: String? = nil,
		jpegThumbnail: Data? = nil,
		thumbnail: OutgoingLinkPreviewThumbnailContent? = nil
	) {
		self.matchedText = matchedText
		self.title = title
		self.description = description
		self.jpegThumbnail = jpegThumbnail
		self.thumbnail = thumbnail
	}
}

public enum OutgoingTextFont: Equatable, Sendable {
	case system
	case systemText
	case fbScript
	case systemBold
	case morningbreezeRegular
	case calistogaRegular
	case exo2Extrabold
	case courierprimeBold
	case unrecognized(Int)
}

public struct OutgoingTextContent: Equatable, Sendable {
	public let text: String
	public let mentions: [String]
	public let mentionAll: Bool
	public let isForwarded: Bool
	public let forwardingScore: UInt32?
	public let quoted: OutgoingQuotedTextContent?
	public let linkPreview: OutgoingLinkPreviewContent?
	public let backgroundARGB: UInt32?
	public let font: OutgoingTextFont?
	public let ephemeralExpiration: UInt32?

	public init(
		text: String,
		mentions: [String] = [],
		mentionAll: Bool = false,
		isForwarded: Bool = false,
		forwardingScore: UInt32? = nil,
		quoted: OutgoingQuotedTextContent? = nil,
		linkPreview: OutgoingLinkPreviewContent? = nil,
		backgroundARGB: UInt32? = nil,
		font: OutgoingTextFont? = nil,
		ephemeralExpiration: UInt32? = nil
	) {
		self.text = text
		self.mentions = mentions
		self.mentionAll = mentionAll
		self.isForwarded = isForwarded
		self.forwardingScore = forwardingScore
		self.quoted = quoted
		self.linkPreview = linkPreview
		self.backgroundARGB = backgroundARGB
		self.font = font
		self.ephemeralExpiration = ephemeralExpiration
	}
}

public struct OutgoingAlbumContent: Equatable, Sendable {
	public let expectedImageCount: UInt32?
	public let expectedVideoCount: UInt32?

	public init(expectedImageCount: UInt32? = nil, expectedVideoCount: UInt32? = nil) {
		self.expectedImageCount = expectedImageCount
		self.expectedVideoCount = expectedVideoCount
	}
}

public struct OutgoingLimitSharingContent: Equatable, Sendable {
	public let sharingLimited: Bool
	public let settingTimestampMilliseconds: Int64

	public init(sharingLimited: Bool, settingTimestampMilliseconds: Int64) {
		self.sharingLimited = sharingLimited
		self.settingTimestampMilliseconds = settingTimestampMilliseconds
	}
}

public enum OutgoingButtonReplyStyle: Equatable, Sendable {
	case plain
	case template
}

public struct OutgoingButtonReplyContent: Equatable, Sendable {
	public let style: OutgoingButtonReplyStyle
	public let id: String
	public let displayText: String
	public let index: UInt32

	public init(style: OutgoingButtonReplyStyle, id: String, displayText: String, index: UInt32) {
		self.style = style
		self.id = id
		self.displayText = displayText
		self.index = index
	}
}

public struct OutgoingListReplyContent: Equatable, Sendable {
	public let title: String
	public let selectedRowID: String
	public let description: String?

	public init(title: String, selectedRowID: String, description: String? = nil) {
		self.title = title
		self.selectedRowID = selectedRowID
		self.description = description
	}
}

public struct OutgoingDisappearingMessagesContent: Equatable, Sendable {
	public static let defaultExpirationSeconds: UInt32 = 604_800

	public let expirationSeconds: UInt32

	public init(expirationSeconds: UInt32) {
		self.expirationSeconds = expirationSeconds
	}

	public init(enabled: Bool) {
		self.expirationSeconds = enabled ? Self.defaultExpirationSeconds : 0
	}
}

public struct OutgoingProductContent: Equatable, Sendable {
	public let productID: String?
	public let title: String?
	public let description: String?
	public let currencyCode: String?
	public let priceAmount1000: Int64?
	public let retailerID: String?
	public let url: String?
	public let productImageCount: UInt32?
	public let firstImageID: String?
	public let salePriceAmount1000: Int64?
	public let signedURL: String?
	public let businessOwnerJID: String?
	public let body: String?
	public let footer: String?
	public let jpegThumbnail: Data?

	public init(
		productID: String? = nil,
		title: String? = nil,
		description: String? = nil,
		currencyCode: String? = nil,
		priceAmount1000: Int64? = nil,
		retailerID: String? = nil,
		url: String? = nil,
		productImageCount: UInt32? = nil,
		firstImageID: String? = nil,
		salePriceAmount1000: Int64? = nil,
		signedURL: String? = nil,
		businessOwnerJID: String? = nil,
		body: String? = nil,
		footer: String? = nil,
		jpegThumbnail: Data? = nil
	) {
		self.productID = productID
		self.title = title
		self.description = description
		self.currencyCode = currencyCode
		self.priceAmount1000 = priceAmount1000
		self.retailerID = retailerID
		self.url = url
		self.productImageCount = productImageCount
		self.firstImageID = firstImageID
		self.salePriceAmount1000 = salePriceAmount1000
		self.signedURL = signedURL
		self.businessOwnerJID = businessOwnerJID
		self.body = body
		self.footer = footer
		self.jpegThumbnail = jpegThumbnail
	}
}

public struct OutgoingDocumentContent: Equatable, Sendable {
	public let mimetype: String
	public let fileName: String?
	public let title: String?
	public let pageCount: UInt32?
	public let caption: String?
	public let jpegThumbnail: Data?

	public init(
		mimetype: String,
		fileName: String? = nil,
		title: String? = nil,
		pageCount: UInt32? = nil,
		caption: String? = nil,
		jpegThumbnail: Data? = nil
	) {
		self.mimetype = mimetype
		self.fileName = fileName
		self.title = title
		self.pageCount = pageCount
		self.caption = caption
		self.jpegThumbnail = jpegThumbnail
	}
}

public struct OutgoingAudioContent: Equatable, Sendable {
	public let mimetype: String
	public let seconds: UInt32?
	public let isVoiceMessage: Bool
	public let waveform: Data?

	public init(
		mimetype: String,
		seconds: UInt32? = nil,
		isVoiceMessage: Bool = false,
		waveform: Data? = nil
	) {
		self.mimetype = mimetype
		self.seconds = seconds
		self.isVoiceMessage = isVoiceMessage
		self.waveform = waveform
	}
}

public struct OutgoingVideoContent: Equatable, Sendable {
	public let mimetype: String
	public let caption: String?
	public let seconds: UInt32?
	public let width: UInt32?
	public let height: UInt32?
	public let isGIFPlayback: Bool
	public let jpegThumbnail: Data?

	public init(
		mimetype: String,
		caption: String? = nil,
		seconds: UInt32? = nil,
		width: UInt32? = nil,
		height: UInt32? = nil,
		isGIFPlayback: Bool = false,
		jpegThumbnail: Data? = nil
	) {
		self.mimetype = mimetype
		self.caption = caption
		self.seconds = seconds
		self.width = width
		self.height = height
		self.isGIFPlayback = isGIFPlayback
		self.jpegThumbnail = jpegThumbnail
	}
}

public struct OutgoingStickerContent: Equatable, Sendable {
	public let mimetype: String
	public let width: UInt32?
	public let height: UInt32?
	public let isAnimated: Bool
	public let pngThumbnail: Data?

	public init(
		mimetype: String = "image/webp",
		width: UInt32? = nil,
		height: UInt32? = nil,
		isAnimated: Bool = false,
		pngThumbnail: Data? = nil
	) {
		self.mimetype = mimetype
		self.width = width
		self.height = height
		self.isAnimated = isAnimated
		self.pngThumbnail = pngThumbnail
	}
}

public struct OutgoingLocationContent: Equatable, Sendable {
	public let latitude: Double
	public let longitude: Double
	public let name: String?
	public let address: String?
	public let url: String?
	public let jpegThumbnail: Data?

	public init(
		latitude: Double,
		longitude: Double,
		name: String? = nil,
		address: String? = nil,
		url: String? = nil,
		jpegThumbnail: Data? = nil
	) {
		self.latitude = latitude
		self.longitude = longitude
		self.name = name
		self.address = address
		self.url = url
		self.jpegThumbnail = jpegThumbnail
	}
}

public struct OutgoingLiveLocationContent: Equatable, Sendable {
	public let latitude: Double
	public let longitude: Double
	public let accuracyInMeters: UInt32?
	public let speedInMetersPerSecond: Float?
	public let degreesClockwiseFromMagneticNorth: UInt32?
	public let caption: String?
	public let sequenceNumber: Int64?
	public let timeOffsetSeconds: UInt32?
	public let jpegThumbnail: Data?

	public init(
		latitude: Double,
		longitude: Double,
		accuracyInMeters: UInt32? = nil,
		speedInMetersPerSecond: Float? = nil,
		degreesClockwiseFromMagneticNorth: UInt32? = nil,
		caption: String? = nil,
		sequenceNumber: Int64? = nil,
		timeOffsetSeconds: UInt32? = nil,
		jpegThumbnail: Data? = nil
	) {
		self.latitude = latitude
		self.longitude = longitude
		self.accuracyInMeters = accuracyInMeters
		self.speedInMetersPerSecond = speedInMetersPerSecond
		self.degreesClockwiseFromMagneticNorth = degreesClockwiseFromMagneticNorth
		self.caption = caption
		self.sequenceNumber = sequenceNumber
		self.timeOffsetSeconds = timeOffsetSeconds
		self.jpegThumbnail = jpegThumbnail
	}
}

public struct OutgoingEventContent: Equatable, Sendable {
	public let name: String
	public let description: String?
	public let startTime: Int64
	public let endTime: Int64?
	public let joinLink: String?
	public let location: OutgoingLocationContent?
	public let isCanceled: Bool?
	public let extraGuestsAllowed: Bool?
	public let isScheduledCall: Bool?
	public let messageSecret: Data?

	public init(
		name: String,
		description: String? = nil,
		startTime: Int64,
		endTime: Int64? = nil,
		joinLink: String? = nil,
		location: OutgoingLocationContent? = nil,
		isCanceled: Bool? = nil,
		extraGuestsAllowed: Bool? = nil,
		isScheduledCall: Bool? = nil,
		messageSecret: Data? = nil
	) {
		self.name = name
		self.description = description
		self.startTime = startTime
		self.endTime = endTime
		self.joinLink = joinLink
		self.location = location
		self.isCanceled = isCanceled
		self.extraGuestsAllowed = extraGuestsAllowed
		self.isScheduledCall = isScheduledCall
		self.messageSecret = messageSecret
	}
}

public struct OutgoingContactContent: Equatable, Sendable {
	public let displayName: String
	public let vcard: String

	public init(displayName: String, vcard: String) {
		self.displayName = displayName
		self.vcard = vcard
	}
}

public struct OutgoingPollContent: Equatable, Sendable {
	public let name: String
	public let options: [String]
	public let selectableOptionsCount: UInt32
	public let encryptedKey: Data?
	public let messageSecret: Data?
	public let isAnnouncementGroup: Bool

	public init(
		name: String,
		options: [String],
		selectableOptionsCount: UInt32,
		encryptedKey: Data? = nil,
		messageSecret: Data? = nil,
		isAnnouncementGroup: Bool = false
	) {
		self.name = name
		self.options = options
		self.selectableOptionsCount = selectableOptionsCount
		self.encryptedKey = encryptedKey
		self.messageSecret = messageSecret
		self.isAnnouncementGroup = isAnnouncementGroup
	}

	public func validate() throws {
		if name.isEmpty {
			throw OutgoingPollContentValidationError.emptyName
		}

		if options.isEmpty {
			throw OutgoingPollContentValidationError.emptyOptions
		}

		if let emptyOptionIndex = options.firstIndex(where: \.isEmpty) {
			throw OutgoingPollContentValidationError.emptyOption(index: emptyOptionIndex)
		}

		if selectableOptionsCount > options.count {
			throw OutgoingPollContentValidationError.invalidSelectableOptionsCount(
				selectableOptionsCount: selectableOptionsCount,
				optionCount: options.count
			)
		}
	}
}

public enum OutgoingPollContentValidationError: Error, Equatable, Sendable {
	case emptyName
	case emptyOptions
	case emptyOption(index: Int)
	case invalidSelectableOptionsCount(selectableOptionsCount: UInt32, optionCount: Int)
}

public struct OutgoingGroupInviteContent: Equatable, Sendable {
	public let groupJID: String
	public let inviteCode: String
	public let inviteExpiration: Int64
	public let groupName: String
	public let caption: String?
	public let jpegThumbnail: Data?

	public init(
		groupJID: String,
		inviteCode: String,
		inviteExpiration: Int64,
		groupName: String,
		caption: String? = nil,
		jpegThumbnail: Data? = nil
	) {
		self.groupJID = groupJID
		self.inviteCode = inviteCode
		self.inviteExpiration = inviteExpiration
		self.groupName = groupName
		self.caption = caption
		self.jpegThumbnail = jpegThumbnail
	}
}
