import Foundation

extension WhatsAppClient {
	public func downloadMedia(_ request: MediaDownloadRequest) async throws -> Data {
		try await mediaDownloader.download(request)
	}

	public func downloadMedia(
		_ request: MediaDownloadRequest,
		reuploadRequest: @Sendable () async throws -> MediaDownloadRequest
	) async throws -> Data {
		try await mediaDownloader.download(request, reuploadRequest: reuploadRequest)
	}

	public func downloadMedia(
		_ request: MediaDownloadRequest,
		updatingExpiredMediaFor key: WhatsAppMessageKey,
		timeout: Duration = .seconds(60),
		randomBytes: @escaping @Sendable (Int) throws -> Data = MessageIDGenerator.secureRandomBytes(count:)
	) async throws -> Data {
		try await mediaDownloader.download(request) {
			try await self.updateMediaDownloadRequest(
				request,
				for: key,
				timeout: timeout,
				randomBytes: randomBytes
			)
		}
	}

	public func downloadMedia(from content: ReceivedMessageContent) async throws -> Data? {
		guard let request = try content.mediaDownloadRequest() else {
			return nil
		}

		return try await downloadMedia(request)
	}

	public func downloadMedia(
		from content: ReceivedMessageContent,
		updatingExpiredMediaFor key: WhatsAppMessageKey,
		timeout: Duration = .seconds(60),
		randomBytes: @escaping @Sendable (Int) throws -> Data = MessageIDGenerator.secureRandomBytes(count:)
	) async throws -> Data? {
		guard let request = try content.mediaDownloadRequest() else {
			return nil
		}

		return try await downloadMedia(
			request,
			updatingExpiredMediaFor: key,
			timeout: timeout,
			randomBytes: randomBytes
		)
	}

	public func downloadMedia(from message: ReceivedMessage) async throws -> Data? {
		try await downloadMedia(from: message.content)
	}

	public func downloadMedia(
		from message: ReceivedMessage,
		updatingExpiredMediaWithTimeout timeout: Duration = .seconds(60),
		randomBytes: @escaping @Sendable (Int) throws -> Data = MessageIDGenerator.secureRandomBytes(count:)
	) async throws -> Data? {
		try await downloadMedia(
			from: message.content,
			updatingExpiredMediaFor: WhatsAppMessageKey(
				remoteJID: message.from,
				fromMe: message.fromMe ?? false,
				id: message.id,
				participant: message.keyParticipant ?? message.participant
			),
			timeout: timeout,
			randomBytes: randomBytes
		)
	}
}
