import Foundation

extension WhatsAppClient {
	public func sendImageMessage(
		to destinationJID: String,
		imageData: Data,
		caption: String? = nil,
		viewOnce: Bool = false,
		albumParentKey: WhatsAppMessageKey? = nil,
		messageID: String? = nil
	) async throws -> String {
		guard let mediaUploader else {
			throw WhatsAppClientError.missingMediaUploader
		}

		guard let messageDeviceResolver else {
			throw WhatsAppClientError.missingMessageDeviceResolver
		}

		let mediaKey = try mediaKeyGenerator.makeMediaKey()
		let encryptedMedia = try MediaEncryption.encrypt(imageData, mediaKey: mediaKey, mediaType: .image)
		let upload = try await mediaUploader.upload(
			encryptedMedia.encryptedFile,
			fileEncSha256Base64: encryptedMedia.fileEncSha256.base64EncodedString(),
			mediaType: .image
		)
		let recipientDeviceJIDs = try await messageDeviceResolver.deviceJIDs(for: destinationJID)
		guard let signalSessionPreparer else {
			throw WhatsAppClientError.missingSignalSessionPreparer
		}

		_ = try await signalSessionPreparer.assertSessions(for: recipientDeviceJIDs, force: false)
		var message = wrapViewOnce(MessageContentBuilder.uploadedImage(
			UploadedImageContent(
				url: upload.mediaURL,
				directPath: upload.directPath,
				mediaKey: mediaKey,
				fileEncSha256: encryptedMedia.fileEncSha256,
				fileSha256: encryptedMedia.fileSha256,
				fileLength: UInt64(encryptedMedia.fileLength),
				mediaKeyTimestamp: mediaKeyTimestamp(),
				mimetype: "image/jpeg",
				caption: caption
			)
		), enabled: viewOnce)
		if let albumParentKey {
			message = MessageContentBuilder.withAlbumParent(message, parent: albumParentKey)
		}

		return try await sendDirectMessage(
			to: destinationJID,
			message: message,
			recipientDeviceJIDs: recipientDeviceJIDs,
			messageID: messageID
		)
	}

	public func sendDocumentMessage(
		to destinationJID: String,
		documentData: Data,
		document: OutgoingDocumentContent,
		viewOnce: Bool = false,
		messageID: String? = nil
	) async throws -> String {
		let uploaded = try await uploadMedia(documentData, mediaType: .document)
		return try await sendResolvedMessage(
			to: destinationJID,
			message: wrapViewOnce(MessageContentBuilder.uploadedDocument(UploadedDocumentContent(
				url: uploaded.result.mediaURL,
				directPath: uploaded.result.directPath,
				mediaKey: uploaded.mediaKey,
				fileEncSha256: uploaded.encryptedMedia.fileEncSha256,
				fileSha256: uploaded.encryptedMedia.fileSha256,
				fileLength: UInt64(uploaded.encryptedMedia.fileLength),
				mediaKeyTimestamp: mediaKeyTimestamp(),
				document: document
			)), enabled: viewOnce),
			messageID: messageID
		)
	}

	public func sendAudioMessage(
		to destinationJID: String,
		audioData: Data,
		audio: OutgoingAudioContent,
		viewOnce: Bool = false,
		messageID: String? = nil
	) async throws -> String {
		let uploaded = try await uploadMedia(audioData, mediaType: .audio)
		return try await sendResolvedMessage(
			to: destinationJID,
			message: wrapViewOnce(MessageContentBuilder.uploadedAudio(UploadedAudioContent(
				url: uploaded.result.mediaURL,
				directPath: uploaded.result.directPath,
				mediaKey: uploaded.mediaKey,
				fileEncSha256: uploaded.encryptedMedia.fileEncSha256,
				fileSha256: uploaded.encryptedMedia.fileSha256,
				fileLength: UInt64(uploaded.encryptedMedia.fileLength),
				mediaKeyTimestamp: mediaKeyTimestamp(),
				audio: audio
			)), enabled: viewOnce),
			messageID: messageID
		)
	}

	public func sendVideoMessage(
		to destinationJID: String,
		videoData: Data,
		video: OutgoingVideoContent,
		viewOnce: Bool = false,
		albumParentKey: WhatsAppMessageKey? = nil,
		messageID: String? = nil
	) async throws -> String {
		let uploaded = try await uploadMedia(videoData, mediaType: .video)
		var message = wrapViewOnce(MessageContentBuilder.uploadedVideo(UploadedVideoContent(
			url: uploaded.result.mediaURL,
			directPath: uploaded.result.directPath,
			mediaKey: uploaded.mediaKey,
			fileEncSha256: uploaded.encryptedMedia.fileEncSha256,
			fileSha256: uploaded.encryptedMedia.fileSha256,
			fileLength: UInt64(uploaded.encryptedMedia.fileLength),
			mediaKeyTimestamp: mediaKeyTimestamp(),
			video: video
		)), enabled: viewOnce)
		if let albumParentKey {
			message = MessageContentBuilder.withAlbumParent(message, parent: albumParentKey)
		}

		return try await sendResolvedMessage(
			to: destinationJID,
			message: message,
			messageID: messageID
		)
	}

	public func sendStickerMessage(
		to destinationJID: String,
		stickerData: Data,
		sticker: OutgoingStickerContent = OutgoingStickerContent(),
		viewOnce: Bool = false,
		messageID: String? = nil
	) async throws -> String {
		let uploaded = try await uploadMedia(stickerData, mediaType: .sticker)
		return try await sendResolvedMessage(
			to: destinationJID,
			message: wrapViewOnce(MessageContentBuilder.uploadedSticker(UploadedStickerContent(
				url: uploaded.result.mediaURL,
				directPath: uploaded.result.directPath,
				mediaKey: uploaded.mediaKey,
				fileEncSha256: uploaded.encryptedMedia.fileEncSha256,
				fileSha256: uploaded.encryptedMedia.fileSha256,
				fileLength: UInt64(uploaded.encryptedMedia.fileLength),
				mediaKeyTimestamp: mediaKeyTimestamp(),
				sticker: sticker
			)), enabled: viewOnce),
			messageID: messageID
		)
	}

	public func sendReactionMessage(
		to destinationJID: String,
		reaction: String,
		target: MessageReactionTarget,
		timestampMilliseconds: Int64? = nil,
		messageID: String? = nil
	) async throws -> String {
		guard let messageDeviceResolver else {
			throw WhatsAppClientError.missingMessageDeviceResolver
		}

		let recipientDeviceJIDs = try await messageDeviceResolver.deviceJIDs(for: destinationJID)
		guard let signalSessionPreparer else {
			throw WhatsAppClientError.missingSignalSessionPreparer
		}

		_ = try await signalSessionPreparer.assertSessions(for: recipientDeviceJIDs, force: false)
		return try await sendDirectMessage(
			to: destinationJID,
			message: MessageContentBuilder.reaction(
				reaction,
				to: target,
				timestampMilliseconds: timestampMilliseconds ?? Int64(Date().timeIntervalSince1970 * 1000)
			),
			recipientDeviceJIDs: recipientDeviceJIDs,
			messageID: messageID
		)
	}

	public func sendLocationMessage(
		to destinationJID: String,
		location: OutgoingLocationContent,
		viewOnce: Bool = false,
		messageID: String? = nil
	) async throws -> String {
		guard let messageDeviceResolver else {
			throw WhatsAppClientError.missingMessageDeviceResolver
		}

		let recipientDeviceJIDs = try await messageDeviceResolver.deviceJIDs(for: destinationJID)
		guard let signalSessionPreparer else {
			throw WhatsAppClientError.missingSignalSessionPreparer
		}

		_ = try await signalSessionPreparer.assertSessions(for: recipientDeviceJIDs, force: false)
		return try await sendDirectMessage(
			to: destinationJID,
			message: wrapViewOnce(MessageContentBuilder.location(location), enabled: viewOnce),
			recipientDeviceJIDs: recipientDeviceJIDs,
			messageID: messageID
		)
	}

	public func sendRequestPhoneNumberMessage(
		to destinationJID: String,
		messageID: String? = nil
	) async throws -> String {
		return try await sendResolvedMessage(
			to: destinationJID,
			message: MessageContentBuilder.requestPhoneNumber(),
			messageID: messageID
		)
	}

	public func sendSharePhoneNumberMessage(
		to destinationJID: String,
		messageID: String? = nil
	) async throws -> String {
		return try await sendResolvedMessage(
			to: destinationJID,
			message: MessageContentBuilder.sharePhoneNumber(),
			messageID: messageID
		)
	}

	public func sendLiveLocationMessage(
		to destinationJID: String,
		location: OutgoingLiveLocationContent,
		viewOnce: Bool = false,
		messageID: String? = nil
	) async throws -> String {
		guard let messageDeviceResolver else {
			throw WhatsAppClientError.missingMessageDeviceResolver
		}

		let recipientDeviceJIDs = try await messageDeviceResolver.deviceJIDs(for: destinationJID)
		guard let signalSessionPreparer else {
			throw WhatsAppClientError.missingSignalSessionPreparer
		}

		_ = try await signalSessionPreparer.assertSessions(for: recipientDeviceJIDs, force: false)
		return try await sendDirectMessage(
			to: destinationJID,
			message: wrapViewOnce(MessageContentBuilder.liveLocation(location), enabled: viewOnce),
			recipientDeviceJIDs: recipientDeviceJIDs,
			messageID: messageID
		)
	}

	public func sendContactMessage(
		to destinationJID: String,
		contact: OutgoingContactContent,
		viewOnce: Bool = false,
		messageID: String? = nil
	) async throws -> String {
		guard let messageDeviceResolver else {
			throw WhatsAppClientError.missingMessageDeviceResolver
		}

		let recipientDeviceJIDs = try await messageDeviceResolver.deviceJIDs(for: destinationJID)
		guard let signalSessionPreparer else {
			throw WhatsAppClientError.missingSignalSessionPreparer
		}

		_ = try await signalSessionPreparer.assertSessions(for: recipientDeviceJIDs, force: false)
		return try await sendDirectMessage(
			to: destinationJID,
			message: wrapViewOnce(MessageContentBuilder.contact(contact), enabled: viewOnce),
			recipientDeviceJIDs: recipientDeviceJIDs,
			messageID: messageID
		)
	}

	public func sendContactsMessage(
		to destinationJID: String,
		displayName: String,
		contacts: [OutgoingContactContent],
		viewOnce: Bool = false,
		messageID: String? = nil
	) async throws -> String {
		guard let messageDeviceResolver else {
			throw WhatsAppClientError.missingMessageDeviceResolver
		}

		let recipientDeviceJIDs = try await messageDeviceResolver.deviceJIDs(for: destinationJID)
		guard let signalSessionPreparer else {
			throw WhatsAppClientError.missingSignalSessionPreparer
		}

		_ = try await signalSessionPreparer.assertSessions(for: recipientDeviceJIDs, force: false)
		return try await sendDirectMessage(
			to: destinationJID,
			message: wrapViewOnce(
				MessageContentBuilder.contacts(displayName: displayName, contacts: contacts),
				enabled: viewOnce
			),
			recipientDeviceJIDs: recipientDeviceJIDs,
			messageID: messageID
		)
	}

	public func sendPollMessage(
		to destinationJID: String,
		poll: OutgoingPollContent,
		viewOnce: Bool = false,
		messageID: String? = nil
	) async throws -> String {
		let message = try MessageContentBuilder.poll(poll)

		return try await sendResolvedMessage(
			to: destinationJID,
			message: wrapViewOnce(message, enabled: viewOnce),
			messageID: messageID
		)
	}

	public func sendEventMessage(
		to destinationJID: String,
		event: OutgoingEventContent,
		viewOnce: Bool = false,
		messageID: String? = nil
	) async throws -> String {
		try await sendResolvedMessage(
			to: destinationJID,
			message: wrapViewOnce(MessageContentBuilder.event(event), enabled: viewOnce),
			messageID: messageID
		)
	}

	public func sendEventResponseMessage(
		to destinationJID: String,
		target: EventCreationMessageTarget,
		response: OutgoingEventResponseContent,
		eventCreatorJID: String,
		responderJID: String,
		eventMessageSecret: Data,
		messageID: String? = nil,
		eventResponseCipher: EventResponseCipher = EventResponseCipher()
	) async throws -> String {
		let encrypted = try eventResponseCipher.encrypt(
			response,
			eventMessageID: target.messageID,
			eventCreatorJID: eventCreatorJID,
			responderJID: responderJID,
			eventMessageSecret: eventMessageSecret
		)

		return try await sendResolvedMessage(
			to: destinationJID,
			message: MessageContentBuilder.encryptedEventResponse(target: target, encrypted: encrypted),
			messageID: messageID
		)
	}

	public func sendGroupInviteMessage(
		to destinationJID: String,
		invite: OutgoingGroupInviteContent,
		viewOnce: Bool = false,
		messageID: String? = nil
	) async throws -> String {
		return try await sendResolvedMessage(
			to: destinationJID,
			message: wrapViewOnce(MessageContentBuilder.groupInvite(invite), enabled: viewOnce),
			messageID: messageID
		)
	}

	public func sendDeleteMessage(
		target: WhatsAppMessageKey,
		messageID: String? = nil
	) async throws -> String {
		guard let destinationJID = target.remoteJID else {
			throw WhatsAppClientError.missingMessageDestination
		}

		return try await sendResolvedMessage(
			to: destinationJID,
			message: MessageContentBuilder.delete(target: target),
			messageID: messageID,
			additionalAttributes: [
				"edit": destinationJID.isGroupJID && !target.fromMe ? "8" : "7"
			]
		)
	}

	public func sendEditMessage(
		target: WhatsAppMessageKey,
		text: String,
		mentions: [String] = [],
		mentionAll: Bool = false,
		isForwarded: Bool = false,
		forwardingScore: UInt32? = nil,
		timestampMilliseconds: Int64? = nil,
		messageID: String? = nil
	) async throws -> String {
		guard let destinationJID = target.remoteJID else {
			throw WhatsAppClientError.missingMessageDestination
		}

		return try await sendResolvedMessage(
			to: destinationJID,
			message: MessageContentBuilder.edit(
				target: target,
				message: MessageContentBuilder.text(
					text,
					mentions: mentions,
					mentionAll: mentionAll,
					isForwarded: isForwarded,
					forwardingScore: forwardingScore
				),
				timestampMilliseconds: timestampMilliseconds ?? Int64(Date().timeIntervalSince1970 * 1000)
			),
			messageID: messageID,
			additionalAttributes: ["edit": "1"]
		)
	}

	public func sendPinMessage(
		target: WhatsAppMessageKey,
		action: MessagePinAction,
		duration: UInt32 = 86_400,
		timestampMilliseconds: Int64? = nil,
		messageID: String? = nil
	) async throws -> String {
		guard let destinationJID = target.remoteJID else {
			throw WhatsAppClientError.missingMessageDestination
		}

		return try await sendResolvedMessage(
			to: destinationJID,
			message: MessageContentBuilder.pin(
				target: target,
				action: action,
				duration: duration,
				timestampMilliseconds: timestampMilliseconds ?? Int64(Date().timeIntervalSince1970 * 1000)
			),
			messageID: messageID,
			additionalAttributes: ["edit": "2"]
		)
	}

	func sendDirectMessage(
		to destinationJID: String,
		message: Proto_Message,
		recipientDeviceJIDs: [String],
		messageID: String?,
		additionalAttributes: [String: String] = [:],
		additionalNodes: [BinaryNode] = []
	) async throws -> String {
		guard let messageEncryptor else {
			throw WhatsAppClientError.missingMessageEncryptor
		}

		let resolvedMessageID = try messageID ?? messageIDGenerator.generateV2(
			userID: authenticationState?.credentials.me?.id
		)
		let tokenNodes: [BinaryNode] = if serverProps.privacyTokenOnOneToOne {
			await trustedContactTokenNodes(
				for: destinationJID,
				additionalAttributes: additionalAttributes
			)
		} else {
			[]
		}
		let relayAdditionalNodes = additionalNodes + tokenNodes
		let stanza = try await MessageRelayBuilder(
			encoder: messageEncoder,
			encryptor: messageEncryptor
		).buildDirectMessageStanza(
			to: destinationJID,
			messageID: resolvedMessageID,
			message: message,
			recipientDeviceJIDs: recipientDeviceJIDs,
			localJID: authenticationState?.credentials.me?.id,
			localLID: authenticationState?.credentials.me?.lid,
			additionalAttributes: additionalAttributes,
			additionalNodes: relayAdditionalNodes
		)
		try await sendNode(stanza)
		await scheduleTrustedContactTokenIssueAfterSend(
			to: destinationJID,
			message: message,
			additionalAttributes: additionalAttributes
		)
		cacheRecentSentMessage(destinationJID: destinationJID, id: resolvedMessageID, message: message)
		return resolvedMessageID
	}

	func uploadMedia(_ data: Data, mediaType: MediaType) async throws -> UploadedMedia {
		guard let mediaUploader else {
			throw WhatsAppClientError.missingMediaUploader
		}

		let mediaKey = try mediaKeyGenerator.makeMediaKey()
		let encryptedMedia = try MediaEncryption.encrypt(data, mediaKey: mediaKey, mediaType: mediaType)
		let result = try await mediaUploader.upload(
			encryptedMedia.encryptedFile,
			fileEncSha256Base64: encryptedMedia.fileEncSha256.base64EncodedString(),
			mediaType: mediaType
		)
		return UploadedMedia(mediaKey: mediaKey, encryptedMedia: encryptedMedia, result: result)
	}

	func sendResolvedMessage(
		to destinationJID: String,
		message: Proto_Message,
		messageID: String?,
		additionalAttributes: [String: String] = [:],
		additionalNodes: [BinaryNode] = [],
		useUserDevicesCache: Bool = true
	) async throws -> String {
		if destinationJID.isGroupJID && additionalAttributes["edit"] == nil {
			return try await sendGroupMessage(
				to: destinationJID,
				message: message,
				messageID: messageID,
				additionalAttributes: additionalAttributes,
				additionalNodes: additionalNodes,
				useUserDevicesCache: useUserDevicesCache
			)
		}

		let recipientDeviceJIDs = try await getUSyncDevices(
			[destinationJID],
			useCache: useUserDevicesCache,
			ignoreZeroDevices: false
		).map(\.jid)
		guard let signalSessionPreparer else {
			throw WhatsAppClientError.missingSignalSessionPreparer
		}

		_ = try await signalSessionPreparer.assertSessions(for: recipientDeviceJIDs, force: false)
		return try await sendDirectMessage(
			to: destinationJID,
			message: message,
			recipientDeviceJIDs: recipientDeviceJIDs,
			messageID: messageID,
			additionalAttributes: additionalAttributes,
			additionalNodes: additionalNodes
		)
	}

	private func trustedContactTokenNodes(
		for destinationJID: String,
		additionalAttributes: [String: String]
	) async -> [BinaryNode] {
		guard additionalAttributes["category"] != "peer",
			  let tokenNode = await TrustedContactTokenNodeBuilder.build(
			  	for: destinationJID,
			  	keys: authenticationState?.keys
			  ) else {
			return []
		}

		return [tokenNode]
	}

func wrapViewOnce(_ message: Proto_Message, enabled: Bool) -> Proto_Message {
	enabled ? MessageContentBuilder.viewOnce(message) : message
}
}

struct UploadedMedia {
	let mediaKey: Data
	let encryptedMedia: EncryptedMedia
	let result: MediaUploadResult
}
