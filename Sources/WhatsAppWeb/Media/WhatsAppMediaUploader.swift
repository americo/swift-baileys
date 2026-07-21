import Foundation

public protocol MediaConnectionResolving: Sendable {
	func fetchConnection() async throws -> MediaConnectionInfo
}

public protocol MediaUploading: Sendable {
	func upload(data: Data, request: MediaUploadRequest) async throws -> MediaUploadTransportResult?
}

public protocol WhatsAppMediaUploading: Sendable {
	func upload(_ data: Data, fileEncSha256Base64: String, mediaType: MediaType) async throws -> MediaUploadResult
}

public struct MediaUploadTransportResult: Equatable, Sendable {
	public let mediaURL: String
	public let directPath: String
	public let metaHMAC: String?
	public let timestamp: Int?
	public let fileID: Int?

	public init(
		mediaURL: String,
		directPath: String,
		metaHMAC: String? = nil,
		timestamp: Int? = nil,
		fileID: Int? = nil
	) {
		self.mediaURL = mediaURL
		self.directPath = directPath
		self.metaHMAC = metaHMAC
		self.timestamp = timestamp
		self.fileID = fileID
	}
}

public struct MediaUploadResult: Equatable, Sendable {
	public let mediaURL: String
	public let directPath: String
	public let metaHMAC: String?
	public let timestamp: Int?
	public let fileID: Int?

	public init(
		mediaURL: String,
		directPath: String,
		metaHMAC: String? = nil,
		timestamp: Int? = nil,
		fileID: Int? = nil
	) {
		self.mediaURL = mediaURL
		self.directPath = directPath
		self.metaHMAC = metaHMAC
		self.timestamp = timestamp
		self.fileID = fileID
	}
}

public struct WhatsAppMediaUploader: WhatsAppMediaUploading {
	private let connectionResolver: any MediaConnectionResolving
	private let transport: any MediaUploading

	public init(connectionResolver: any MediaConnectionResolving, transport: any MediaUploading) {
		self.connectionResolver = connectionResolver
		self.transport = transport
	}

	public init(
		query: @escaping MediaConnectionResolver.Query,
		transport: any MediaUploading = URLSessionMediaUploadTransport()
	) {
		self.init(
			connectionResolver: MediaConnectionResolver(query: query),
			transport: transport
		)
	}

	public func upload(
		_ data: Data,
		fileEncSha256Base64: String,
		mediaType: MediaType
	) async throws -> MediaUploadResult {
		guard !data.isEmpty else {
			throw WhatsAppMediaUploaderError.emptyUploadData
		}

		let connection = try await connectionResolver.fetchConnection()
		var lastError: (any Error)?
		for host in connection.hosts {
			let request = try MediaUploadRequestBuilder.build(
				hostname: host.hostname,
				authToken: connection.auth,
				fileEncSha256Base64: fileEncSha256Base64,
				mediaType: mediaType
			)
			let result: MediaUploadTransportResult?
			do {
				result = try await transport.upload(data: data, request: request)
			} catch {
				lastError = error
				continue
			}

			if let result {
				guard !result.mediaURL.isEmpty, !result.directPath.isEmpty else {
					continue
				}
				return MediaUploadResult(result: result)
			}
		}

		if let lastError {
			throw lastError
		}

		throw WhatsAppMediaUploaderError.uploadFailed
	}
}

public enum WhatsAppMediaUploaderError: Error, Equatable, Sendable {
	case uploadFailed
	case emptyUploadData
}

extension MediaConnectionResolver: MediaConnectionResolving {}

private extension MediaUploadResult {
	init(result: MediaUploadTransportResult) {
		self.init(
			mediaURL: result.mediaURL,
			directPath: result.directPath,
			metaHMAC: result.metaHMAC,
			timestamp: result.timestamp,
			fileID: result.fileID
		)
	}
}
