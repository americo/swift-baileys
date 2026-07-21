import Foundation

public struct ReceivedImageContent: Equatable, Sendable {
	public let url: String
	public let directPath: String
	public let mediaKey: Data
	public let fileEncSHA256: Data
	public let fileSHA256: Data
	public let fileLength: UInt64
	public let mediaKeyTimestamp: Int64
	public let mimetype: String
	public let caption: String?
	public let jpegThumbnail: Data?

	public init(
		url: String,
		directPath: String,
		mediaKey: Data,
		fileEncSHA256: Data,
		fileSHA256: Data,
		fileLength: UInt64,
		mediaKeyTimestamp: Int64,
		mimetype: String,
		caption: String?,
		jpegThumbnail: Data?
	) {
		self.url = url
		self.directPath = directPath
		self.mediaKey = mediaKey
		self.fileEncSHA256 = fileEncSHA256
		self.fileSHA256 = fileSHA256
		self.fileLength = fileLength
		self.mediaKeyTimestamp = mediaKeyTimestamp
		self.mimetype = mimetype
		self.caption = caption
		self.jpegThumbnail = jpegThumbnail
	}
}

public struct ReceivedDocumentContent: Equatable, Sendable {
	public let url: String
	public let directPath: String
	public let mediaKey: Data
	public let fileEncSHA256: Data
	public let fileSHA256: Data
	public let fileLength: UInt64
	public let mediaKeyTimestamp: Int64
	public let mimetype: String
	public let fileName: String?
	public let title: String?
	public let pageCount: UInt32?

	public init(
		url: String,
		directPath: String,
		mediaKey: Data,
		fileEncSHA256: Data,
		fileSHA256: Data,
		fileLength: UInt64,
		mediaKeyTimestamp: Int64,
		mimetype: String,
		fileName: String?,
		title: String?,
		pageCount: UInt32?
	) {
		self.url = url
		self.directPath = directPath
		self.mediaKey = mediaKey
		self.fileEncSHA256 = fileEncSHA256
		self.fileSHA256 = fileSHA256
		self.fileLength = fileLength
		self.mediaKeyTimestamp = mediaKeyTimestamp
		self.mimetype = mimetype
		self.fileName = fileName
		self.title = title
		self.pageCount = pageCount
	}
}

public struct ReceivedAudioContent: Equatable, Sendable {
	public let url: String
	public let directPath: String
	public let mediaKey: Data
	public let fileEncSHA256: Data
	public let fileSHA256: Data
	public let fileLength: UInt64
	public let mediaKeyTimestamp: Int64
	public let mimetype: String
	public let seconds: UInt32?
	public let isVoiceMessage: Bool
	public let waveform: Data?

	public init(
		url: String,
		directPath: String,
		mediaKey: Data,
		fileEncSHA256: Data,
		fileSHA256: Data,
		fileLength: UInt64,
		mediaKeyTimestamp: Int64,
		mimetype: String,
		seconds: UInt32?,
		isVoiceMessage: Bool,
		waveform: Data?
	) {
		self.url = url
		self.directPath = directPath
		self.mediaKey = mediaKey
		self.fileEncSHA256 = fileEncSHA256
		self.fileSHA256 = fileSHA256
		self.fileLength = fileLength
		self.mediaKeyTimestamp = mediaKeyTimestamp
		self.mimetype = mimetype
		self.seconds = seconds
		self.isVoiceMessage = isVoiceMessage
		self.waveform = waveform
	}
}

public struct ReceivedVideoContent: Equatable, Sendable {
	public let url: String
	public let directPath: String
	public let mediaKey: Data
	public let fileEncSHA256: Data
	public let fileSHA256: Data
	public let fileLength: UInt64
	public let mediaKeyTimestamp: Int64
	public let mimetype: String
	public let caption: String?
	public let seconds: UInt32?
	public let width: UInt32?
	public let height: UInt32?
	public let isGIFPlayback: Bool
	public let jpegThumbnail: Data?

	public init(
		url: String,
		directPath: String,
		mediaKey: Data,
		fileEncSHA256: Data,
		fileSHA256: Data,
		fileLength: UInt64,
		mediaKeyTimestamp: Int64,
		mimetype: String,
		caption: String?,
		seconds: UInt32?,
		width: UInt32?,
		height: UInt32?,
		isGIFPlayback: Bool,
		jpegThumbnail: Data?
	) {
		self.url = url
		self.directPath = directPath
		self.mediaKey = mediaKey
		self.fileEncSHA256 = fileEncSHA256
		self.fileSHA256 = fileSHA256
		self.fileLength = fileLength
		self.mediaKeyTimestamp = mediaKeyTimestamp
		self.mimetype = mimetype
		self.caption = caption
		self.seconds = seconds
		self.width = width
		self.height = height
		self.isGIFPlayback = isGIFPlayback
		self.jpegThumbnail = jpegThumbnail
	}
}

public struct ReceivedStickerContent: Equatable, Sendable {
	public let url: String
	public let directPath: String
	public let mediaKey: Data
	public let fileEncSHA256: Data
	public let fileSHA256: Data
	public let fileLength: UInt64
	public let mediaKeyTimestamp: Int64
	public let mimetype: String
	public let width: UInt32?
	public let height: UInt32?
	public let isAnimated: Bool
	public let isAvatar: Bool
	public let isAISticker: Bool
	public let isLottie: Bool
	public let pngThumbnail: Data?

	public init(
		url: String,
		directPath: String,
		mediaKey: Data,
		fileEncSHA256: Data,
		fileSHA256: Data,
		fileLength: UInt64,
		mediaKeyTimestamp: Int64,
		mimetype: String,
		width: UInt32?,
		height: UInt32?,
		isAnimated: Bool,
		isAvatar: Bool,
		isAISticker: Bool,
		isLottie: Bool,
		pngThumbnail: Data?
	) {
		self.url = url
		self.directPath = directPath
		self.mediaKey = mediaKey
		self.fileEncSHA256 = fileEncSHA256
		self.fileSHA256 = fileSHA256
		self.fileLength = fileLength
		self.mediaKeyTimestamp = mediaKeyTimestamp
		self.mimetype = mimetype
		self.width = width
		self.height = height
		self.isAnimated = isAnimated
		self.isAvatar = isAvatar
		self.isAISticker = isAISticker
		self.isLottie = isLottie
		self.pngThumbnail = pngThumbnail
	}
}
