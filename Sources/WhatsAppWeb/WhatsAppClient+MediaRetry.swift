import Foundation

extension WhatsAppClient {
	@discardableResult
	public func requestMediaReupload(
		for key: WhatsAppMessageKey,
		mediaKey: Data,
		randomBytes: @Sendable (Int) throws -> Data = MessageIDGenerator.secureRandomBytes(count:)
	) async throws -> BinaryNode {
		guard let credentials = authenticationState?.credentials else {
			throw WhatsAppClientError.missingAuthenticatedUser
		}
		let meID: String
		do {
			meID = try credentials.assertMeID()
		} catch {
			throw WhatsAppClientError.missingAuthenticatedUser
		}

		let node = try MediaRetryCipher.encryptRetryRequest(
			key: key,
			mediaKey: mediaKey,
			meID: meID,
			randomBytes: randomBytes
		)
		try await sendNode(node)
		return node
	}

	public func updateMediaDownloadRequest(
		_ request: MediaDownloadRequest,
		for key: WhatsAppMessageKey,
		timeout: Duration = .seconds(60),
		randomBytes: @escaping @Sendable (Int) throws -> Data = MessageIDGenerator.secureRandomBytes(count:)
	) async throws -> MediaDownloadRequest {
		try await refreshMediaDownloadRequest(
			request,
			for: key,
			timeout: timeout,
			randomBytes: randomBytes
		).request
	}

	public func updateMediaMessage(
		_ message: ReceivedMessage,
		timeout: Duration = .seconds(60),
		randomBytes: @escaping @Sendable (Int) throws -> Data = MessageIDGenerator.secureRandomBytes(count:)
	) async throws -> ReceivedMessage {
		guard let request = try message.content.mediaDownloadRequest() else {
			throw MediaReuploadRequestError.missingMediaContent
		}

		let key = WhatsAppMessageKey(
			remoteJID: message.from,
			fromMe: message.fromMe ?? false,
			id: message.id,
			participant: message.keyParticipant ?? message.participant
		)
		let refresh = try await refreshMediaDownloadRequest(
			request,
			for: key,
			timeout: timeout,
			randomBytes: randomBytes
		)
		let updated = try message.updatingContent(message.content.updatingMediaLocation(
			url: refresh.request.url.absoluteString,
			directPath: refresh.directPath
		))

		eventContinuation.yield(.messagesUpdated([
			ReceivedMessageUpdate(
				key: key,
				status: nil,
				timestamp: nil,
				content: updated.content
			)
		]))
		return updated
	}

	private func refreshMediaDownloadRequest(
		_ request: MediaDownloadRequest,
		for key: WhatsAppMessageKey,
		timeout: Duration,
		randomBytes: @escaping @Sendable (Int) throws -> Data
	) async throws -> MediaRefreshResult {
		guard let messageID = key.id else {
			throw MediaReuploadRequestError.missingMessageID
		}

		let update = try await mediaUpdateCoordinator.perform(id: messageID, timeout: timeout) {
			_ = try await self.requestMediaReupload(
				for: key,
				mediaKey: request.mediaKey,
				randomBytes: randomBytes
			)
		}

		if let errorCode = update.errorCode {
			throw MediaReuploadRequestError.reuploadError(
				code: errorCode,
				statusCode: update.errorStatusCode
			)
		}

		guard let media = update.media else {
			throw MediaReuploadRequestError.missingRetriedMedia
		}

		let notification = try MediaRetryCipher.decryptRetryNotification(
			media,
			mediaKey: request.mediaKey,
			messageID: messageID
		)
		guard notification.resultCode == Proto_MediaRetryNotification.ResultType.success.rawValue else {
			throw MediaReuploadRequestError.deviceReuploadFailed(
				code: notification.resultCode,
				statusCode: notification.resultStatusCode
			)
		}
		guard let directPath = notification.directPath,
			  let url = MediaDirectPathURLResolver.url(from: directPath) else {
			throw MediaReuploadRequestError.missingDirectPath
		}

		return MediaRefreshResult(
			request: MediaDownloadRequest(
				url: url,
				mediaKey: request.mediaKey,
				mediaType: request.mediaType,
				fileEncSHA256: request.fileEncSHA256,
				fileSHA256: request.fileSHA256
			),
			directPath: directPath
		)
	}
}

public enum MediaReuploadRequestError: Error, Equatable, Sendable {
	case missingMessageID
	case missingMediaContent
	case reuploadError(code: Int, statusCode: Int?)
	case missingRetriedMedia
	case deviceReuploadFailed(code: Int?, statusCode: Int?)
	case missingDirectPath
}

private struct MediaRefreshResult: Equatable, Sendable {
	let request: MediaDownloadRequest
	let directPath: String
}

private extension ReceivedMessage {
	func updatingContent(_ content: ReceivedMessageContent) -> ReceivedMessage {
		ReceivedMessage(
			id: id,
			from: from,
			timestamp: timestamp,
			content: content,
			fromMe: fromMe,
			participant: participant,
			keyParticipant: keyParticipant,
			status: status,
			pushName: pushName,
			stub: stub
		)
	}
}

private extension ReceivedMessageContent {
	func updatingMediaLocation(url: String, directPath: String) throws -> ReceivedMessageContent {
		switch self {
		case .image(let image):
			return .image(ReceivedImageContent(
				url: url,
				directPath: directPath,
				mediaKey: image.mediaKey,
				fileEncSHA256: image.fileEncSHA256,
				fileSHA256: image.fileSHA256,
				fileLength: image.fileLength,
				mediaKeyTimestamp: image.mediaKeyTimestamp,
				mimetype: image.mimetype,
				caption: image.caption,
				jpegThumbnail: image.jpegThumbnail
			))
		case .document(let document):
			return .document(ReceivedDocumentContent(
				url: url,
				directPath: directPath,
				mediaKey: document.mediaKey,
				fileEncSHA256: document.fileEncSHA256,
				fileSHA256: document.fileSHA256,
				fileLength: document.fileLength,
				mediaKeyTimestamp: document.mediaKeyTimestamp,
				mimetype: document.mimetype,
				fileName: document.fileName,
				title: document.title,
				pageCount: document.pageCount
			))
		case .audio(let audio):
			return .audio(ReceivedAudioContent(
				url: url,
				directPath: directPath,
				mediaKey: audio.mediaKey,
				fileEncSHA256: audio.fileEncSHA256,
				fileSHA256: audio.fileSHA256,
				fileLength: audio.fileLength,
				mediaKeyTimestamp: audio.mediaKeyTimestamp,
				mimetype: audio.mimetype,
				seconds: audio.seconds,
				isVoiceMessage: audio.isVoiceMessage,
				waveform: audio.waveform
			))
		case .video(let video):
			return .video(ReceivedVideoContent(
				url: url,
				directPath: directPath,
				mediaKey: video.mediaKey,
				fileEncSHA256: video.fileEncSHA256,
				fileSHA256: video.fileSHA256,
				fileLength: video.fileLength,
				mediaKeyTimestamp: video.mediaKeyTimestamp,
				mimetype: video.mimetype,
				caption: video.caption,
				seconds: video.seconds,
				width: video.width,
				height: video.height,
				isGIFPlayback: video.isGIFPlayback,
				jpegThumbnail: video.jpegThumbnail
			))
		case .sticker(let sticker):
			return .sticker(ReceivedStickerContent(
				url: url,
				directPath: directPath,
				mediaKey: sticker.mediaKey,
				fileEncSHA256: sticker.fileEncSHA256,
				fileSHA256: sticker.fileSHA256,
				fileLength: sticker.fileLength,
				mediaKeyTimestamp: sticker.mediaKeyTimestamp,
				mimetype: sticker.mimetype,
				width: sticker.width,
				height: sticker.height,
				isAnimated: sticker.isAnimated,
				isAvatar: sticker.isAvatar,
				isAISticker: sticker.isAISticker,
				isLottie: sticker.isLottie,
				pngThumbnail: sticker.pngThumbnail
			))
		default:
			throw MediaReuploadRequestError.missingMediaContent
		}
	}
}
