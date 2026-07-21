import Foundation

public enum ReceivedBusinessCallMediaType: Equatable, Sendable {
	case unknown
	case audio
	case video
	case unrecognized(Int)
}

public struct ReceivedBusinessCallContent: Equatable, Sendable {
	public let sessionID: String?
	public let mediaType: ReceivedBusinessCallMediaType?
	public let masterKey: Data?
	public let caption: String?

	public init(
		sessionID: String?,
		mediaType: ReceivedBusinessCallMediaType?,
		masterKey: Data?,
		caption: String?
	) {
		self.sessionID = sessionID
		self.mediaType = mediaType
		self.masterKey = masterKey
		self.caption = caption
	}
}
