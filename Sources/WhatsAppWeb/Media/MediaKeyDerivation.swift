import CryptoKit
import Foundation

public enum MediaType: String, Sendable {
	case audio
	case document
	case gif
	case image
	case ppic
	case product
	case ptt
	case sticker
	case video
	case thumbnailDocument = "thumbnail-document"
	case thumbnailImage = "thumbnail-image"
	case thumbnailVideo = "thumbnail-video"
	case thumbnailLink = "thumbnail-link"
	case mdMessageHistory = "md-msg-hist"
	case mdAppState = "md-app-state"
	case productCatalogImage = "product-catalog-image"
	case paymentBackgroundImage = "payment-bg-image"
	case ptv
	case businessCoverPhoto = "biz-cover-photo"
}

public struct MediaDecryptionKeyInfo: Equatable, Sendable {
	public let iv: Data
	public let cipherKey: Data
	public let macKey: Data
}

public enum MediaKeyDerivation {
	public static func deriveKeys(from mediaKey: Data, mediaType: MediaType) throws -> MediaDecryptionKeyInfo {
		guard !mediaKey.isEmpty else {
			throw MediaKeyDerivationError.emptyMediaKey
		}

		let key = HKDF<SHA256>.deriveKey(
			inputKeyMaterial: SymmetricKey(data: mediaKey),
			salt: Data(),
			info: Data("WhatsApp \(mediaType.hkdfInfo) Keys".utf8),
			outputByteCount: 112
		)
		let expandedKey = key.withUnsafeBytes { Data($0) }

		return MediaDecryptionKeyInfo(
			iv: expandedKey[safe: 0..<16],
			cipherKey: expandedKey[safe: 16..<48],
			macKey: expandedKey[safe: 48..<80]
		)
	}
}

public enum MediaKeyDerivationError: Error, Equatable, Sendable {
	case emptyMediaKey
}

private extension MediaType {
	var hkdfInfo: String {
		switch self {
		case .audio, .ptt:
			"Audio"
		case .document:
			"Document"
		case .gif, .video, .ptv:
			"Video"
		case .image, .product, .sticker, .businessCoverPhoto:
			"Image"
		case .ppic, .productCatalogImage:
			""
		case .thumbnailDocument:
			"Document Thumbnail"
		case .thumbnailImage:
			"Image Thumbnail"
		case .thumbnailVideo:
			"Video Thumbnail"
		case .thumbnailLink:
			"Link Thumbnail"
		case .mdMessageHistory:
			"History"
		case .mdAppState:
			"App State"
		case .paymentBackgroundImage:
			"Payment Background"
		}
	}
}

private extension Data {
	subscript(safe range: Range<Int>) -> Data {
		Data(self[index(startIndex, offsetBy: range.lowerBound)..<index(startIndex, offsetBy: range.upperBound)])
	}
}
