import Foundation

public struct MediaUploadRequest: Equatable, Sendable {
	public let url: URL
	public let headers: [String: String]
}

public enum MediaUploadRequestBuilder {
	public static func build(
		hostname: String,
		authToken: String,
		fileEncSha256Base64: String,
		mediaType: MediaType
	) throws -> MediaUploadRequest {
		guard !hostname.isEmpty else {
			throw MediaUploadRequestBuilderError.emptyHostname
		}
		guard !authToken.isEmpty else {
			throw MediaUploadRequestBuilderError.emptyAuthToken
		}
		guard !fileEncSha256Base64.isEmpty else {
			throw MediaUploadRequestBuilderError.emptyFileEncSHA256
		}

		guard let path = mediaType.uploadPath else {
			throw MediaUploadRequestBuilderError.unsupportedMediaType(mediaType)
		}

		let encodedHash = MediaUploadTokenEncoder.encodeBase64ForUpload(fileEncSha256Base64)
		let auth = authToken.addingPercentEncoding(withAllowedCharacters: Self.uriComponentAllowedCharacters) ?? authToken
		guard let url = URL(string: "https://\(hostname)\(path)/\(encodedHash)?auth=\(auth)&token=\(encodedHash)") else {
			throw MediaUploadRequestBuilderError.invalidURL
		}

		return MediaUploadRequest(
			url: url,
			headers: [
				"Content-Type": "application/octet-stream",
				"Origin": "https://web.whatsapp.com"
			]
		)
	}
}

public enum MediaUploadRequestBuilderError: Error, Equatable, Sendable {
	case emptyHostname
	case emptyAuthToken
	case emptyFileEncSHA256
	case invalidURL
	case unsupportedMediaType(MediaType)
}

private extension MediaUploadRequestBuilder {
	static let uriComponentAllowedCharacters: CharacterSet = {
		var characters = CharacterSet.alphanumerics
		characters.insert(charactersIn: "-_.!~*'()")
		return characters
	}()
}

private extension MediaType {
	var uploadPath: String? {
		switch self {
		case .image, .sticker, .thumbnailLink:
			"/mms/image"
		case .video:
			"/mms/video"
		case .document:
			"/mms/document"
		case .audio:
			"/mms/audio"
		case .productCatalogImage:
			"/product/image"
		case .mdAppState:
			""
		case .mdMessageHistory:
			"/mms/md-app-state"
		case .businessCoverPhoto:
			"/pps/biz-cover-photo"
		case .gif, .ppic, .product, .ptt, .thumbnailDocument, .thumbnailImage, .thumbnailVideo, .paymentBackgroundImage, .ptv:
			nil
		}
	}
}
