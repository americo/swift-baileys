import Foundation

extension WhatsAppClient {
	public func refreshMediaConn(forceGet _: Bool = false) async throws -> MediaConnectionInfo {
		let resolver = MediaConnectionResolver { node, timeout in
			try await self.query(node, timeout: timeout)
		}
		return try await resolver.fetchConnection()
	}

	public func getMediaHost(forceRefresh: Bool = false) async throws -> String {
		guard let host = try await refreshMediaConn(forceGet: forceRefresh).hosts.first?.hostname else {
			throw MediaConnectionResolverError.invalidResponse
		}
		return host
	}

	public func waUploadToServer(
		_ data: Data,
		fileEncSha256Base64: String,
		mediaType: MediaType
	) async throws -> MediaUploadResult {
		guard let mediaUploader else {
			throw WhatsAppClientError.missingMediaUploader
		}

		return try await mediaUploader.upload(data, fileEncSha256Base64: fileEncSha256Base64, mediaType: mediaType)
	}
}
