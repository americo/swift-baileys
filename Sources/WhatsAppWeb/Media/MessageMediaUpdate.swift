import Foundation

public struct RetriedMedia: Equatable, Sendable {
	public let ciphertext: Data
	public let iv: Data

	public init(ciphertext: Data, iv: Data) {
		self.ciphertext = ciphertext
		self.iv = iv
	}
}

public struct MessageMediaUpdate: Equatable, Sendable {
	public let key: WhatsAppMessageKey
	public let media: RetriedMedia?
	public let errorCode: Int?
	public let errorStatusCode: Int?

	public init(
		key: WhatsAppMessageKey,
		media: RetriedMedia? = nil,
		errorCode: Int? = nil,
		errorStatusCode: Int? = nil
	) {
		self.key = key
		self.media = media
		self.errorCode = errorCode
		self.errorStatusCode = errorStatusCode
	}
}
