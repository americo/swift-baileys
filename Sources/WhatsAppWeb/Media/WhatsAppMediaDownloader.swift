import Foundation

protocol MediaDownloading: Sendable {
	func download(from url: URL) async throws -> Data
}

public struct MediaDownloadRequest: Equatable, Sendable {
	public let url: URL
	public let mediaKey: Data
	public let mediaType: MediaType
	public let fileEncSHA256: Data
	public let fileSHA256: Data

	public init(
		url: URL,
		mediaKey: Data,
		mediaType: MediaType,
		fileEncSHA256: Data,
		fileSHA256: Data
	) {
		self.url = url
		self.mediaKey = mediaKey
		self.mediaType = mediaType
		self.fileEncSHA256 = fileEncSHA256
		self.fileSHA256 = fileSHA256
	}

	public func validate() throws {
		guard !mediaKey.isEmpty else {
			throw MediaDownloadRequestValidationError.emptyMediaKey
		}
		guard fileEncSHA256.count == 32 else {
			throw MediaDownloadRequestValidationError.invalidFileEncSHA256
		}
		guard fileSHA256.count == 32 else {
			throw MediaDownloadRequestValidationError.invalidFileSHA256
		}
	}
}

public enum MediaDownloadRequestValidationError: Error, Equatable, Sendable {
	case emptyMediaKey
	case invalidFileEncSHA256
	case invalidFileSHA256
}

struct WhatsAppMediaDownloader: Sendable {
	private let transport: any MediaDownloading

	init(transport: any MediaDownloading) {
		self.transport = transport
	}

	func download(_ request: MediaDownloadRequest) async throws -> Data {
		try request.validate()
		let encryptedFile = try await transport.download(from: request.url)
		return try MediaDecryption.decrypt(
			encryptedFile,
			mediaKey: request.mediaKey,
			mediaType: request.mediaType,
			expectedFileEncSHA256: request.fileEncSHA256,
			expectedFileSHA256: request.fileSHA256
		)
	}

	func download(
		_ request: MediaDownloadRequest,
		reuploadRequest: @Sendable () async throws -> MediaDownloadRequest
	) async throws -> Data {
		do {
			return try await download(request)
		} catch {
			guard let statusCode = MediaReuploadPolicy.statusCode(from: error),
				  MediaReuploadPolicy.requiresReupload(forStatusCode: statusCode) else {
				throw error
			}

			return try await download(reuploadRequest())
		}
	}
}
