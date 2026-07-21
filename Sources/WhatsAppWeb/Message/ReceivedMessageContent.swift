import Foundation

public struct ReceivedMessage: Equatable, Sendable {
	public let id: String
	public let from: String?
	public let timestamp: UInt64?
	public let content: ReceivedMessageContent
	public let fromMe: Bool?
	public let participant: String?
	public let keyParticipant: String?
	public let status: ReceivedMessageStatus?
	public let pushName: String?
	public let stub: ReceivedMessageStubContent?

	public init(
		id: String,
		from: String?,
		timestamp: UInt64?,
		content: ReceivedMessageContent,
		fromMe: Bool? = nil,
		participant: String? = nil,
		keyParticipant: String? = nil,
		status: ReceivedMessageStatus? = nil,
		pushName: String? = nil,
		stub: ReceivedMessageStubContent? = nil
	) {
		self.id = id
		self.from = from
		self.timestamp = timestamp
		self.content = content
		self.fromMe = fromMe
		self.participant = participant
		self.keyParticipant = keyParticipant
		self.status = status
		self.pushName = pushName
		self.stub = stub
	}
}

public enum ReceivedMessageStatus: Equatable, Sendable {
	case error
	case pending
	case serverAck
	case deliveryAck
	case read
	case played
	case unrecognized(Int)
}

public struct ReceivedTextLinkPreviewThumbnailContent: Equatable, Sendable {
	public let directPath: String
	public let mediaKey: Data
	public let mediaKeyTimestamp: Int64?
	public let width: UInt32?
	public let height: UInt32?
	public let fileSha256: Data?
	public let fileEncSha256: Data?

	public init(
		directPath: String,
		mediaKey: Data,
		mediaKeyTimestamp: Int64? = nil,
		width: UInt32? = nil,
		height: UInt32? = nil,
		fileSha256: Data? = nil,
		fileEncSha256: Data? = nil
	) {
		self.directPath = directPath
		self.mediaKey = mediaKey
		self.mediaKeyTimestamp = mediaKeyTimestamp
		self.width = width
		self.height = height
		self.fileSha256 = fileSha256
		self.fileEncSha256 = fileEncSha256
	}
}

public struct ReceivedTextLinkPreviewContent: Equatable, Sendable {
	public let text: String
	public let matchedText: String
	public let title: String?
	public let description: String?
	public let jpegThumbnail: Data?
	public let thumbnail: ReceivedTextLinkPreviewThumbnailContent?

	public init(
		text: String,
		matchedText: String,
		title: String? = nil,
		description: String? = nil,
		jpegThumbnail: Data? = nil,
		thumbnail: ReceivedTextLinkPreviewThumbnailContent? = nil
	) {
		self.text = text
		self.matchedText = matchedText
		self.title = title
		self.description = description
		self.jpegThumbnail = jpegThumbnail
		self.thumbnail = thumbnail
	}
}

public indirect enum ReceivedMessageContent: Equatable, Sendable {
	case text(String)
	case textLinkPreview(ReceivedTextLinkPreviewContent)
	case image(ReceivedImageContent)
	case document(ReceivedDocumentContent)
	case audio(ReceivedAudioContent)
	case video(ReceivedVideoContent)
	case sticker(ReceivedStickerContent)
	case call(ReceivedCallContent)
	case chat(ReceivedChatContent)
	case location(ReceivedLocationContent)
	case liveLocation(ReceivedLiveLocationContent)
	case event(ReceivedEventContent)
	case encryptedEventResponse(ReceivedEncryptedEventResponseContent)
	case scheduledCallCreation(ReceivedScheduledCallCreationContent)
	case scheduledCallEdit(ReceivedScheduledCallEditContent)
	case contact(ReceivedContactContent)
	case contacts(ReceivedContactsContent)
	case requestPhoneNumber(ReceivedRequestPhoneNumberContent)
	case ephemeralSetting(ReceivedEphemeralSettingContent)
	case phoneNumberShared(ReceivedPhoneNumberSharedContent)
	case limitSharing(ReceivedLimitSharingContent)
	case appStateSyncKeyShare(ReceivedAppStateSyncKeyShareContent)
	case appStateSyncKeyRequest(ReceivedAppStateSyncKeyRequestContent)
	case lidMigrationMappingSync(ReceivedLIDMigrationMappingSyncContent)
	case groupMemberLabelChange(ReceivedGroupMemberLabelChangeContent)
	case historySyncNotification(ReceivedHistorySyncNotificationContent)
	case peerDataOperationRequestResponse(ReceivedPeerDataOperationRequestResponseContent)
	case highlyStructured(ReceivedHighlyStructuredMessageContent)
	case groupInvite(ReceivedGroupInviteContent)
	case pollCreation(ReceivedPollCreationContent)
	case pollUpdate(ReceivedPollUpdateContent)
	case pollResultSnapshot(ReceivedPollResultSnapshotContent)
	case reaction(ReceivedReactionContent)
	case messageRevoked(ReceivedMessageRevokedContent)
	case messageEdited(ReceivedMessageEditedContent)
	case messagePin(ReceivedMessagePinContent)
	case messageKeep(ReceivedMessageKeepContent)
	case newsletterAdminInvite(ReceivedNewsletterAdminInviteContent)
	case newsletterFollowerInvite(ReceivedNewsletterFollowerInviteContent)
	case callLog(ReceivedCallLogContent)
	case stickerPack(ReceivedStickerPackContent)
	case messageHistoryBundle(ReceivedMessageHistoryBundleContent)
	case album(ReceivedAlbumContent)
	case order(ReceivedOrderContent)
	case product(ReceivedProductContent)
	case list(ReceivedListContent)
	case buttons(ReceivedButtonsContent)
	case interactive(ReceivedInteractiveContent)
	case buttonsResponse(ReceivedButtonsResponseContent)
	case listResponse(ReceivedListResponseContent)
	case templateButtonReply(ReceivedTemplateButtonReplyContent)
	case interactiveResponse(ReceivedInteractiveResponseContent)
	case statusNotification(ReceivedStatusNotificationContent)
	case statusQuestionAnswer(ReceivedStatusQuestionAnswerContent)
	case statusQuoted(ReceivedStatusQuotedContent)
	case statusStickerInteraction(ReceivedStatusStickerInteractionContent)
	case questionResponse(ReceivedQuestionResponseContent)
	case messageHistoryNotice(ReceivedMessageHistoryNoticeContent)
	case aiRichResponse(ReceivedAIRichResponseContent)
	case sendPayment(ReceivedSendPaymentContent)
	case requestPayment(ReceivedRequestPaymentContent)
	case declinePaymentRequest(ReceivedPaymentRequestActionContent)
	case cancelPaymentRequest(ReceivedPaymentRequestActionContent)
	case paymentInvite(ReceivedPaymentInviteContent)
	case invoice(ReceivedInvoiceContent)
	case placeholder(ReceivedPlaceholderContent)
	case businessCall(ReceivedBusinessCallContent)
	case stickerSyncRMR(ReceivedStickerSyncRMRContent)
	case encryptedComment(ReceivedEncryptedCommentContent)
	case encryptedReaction(ReceivedEncryptedReactionContent)
	case secretEncrypted(ReceivedSecretEncryptedContent)
	case comment(ReceivedCommentContent)
	case stub(ReceivedMessageStubContent)

	public var isForwardable: Bool {
		switch self {
		case .text, .textLinkPreview, .image, .document, .audio, .video, .call, .chat, .sticker,
			 .location, .liveLocation, .event, .encryptedEventResponse, .scheduledCallCreation, .scheduledCallEdit, .contact,
			 .contacts, .requestPhoneNumber, .ephemeralSetting, .phoneNumberShared, .limitSharing,
			 .groupMemberLabelChange, .highlyStructured, .groupInvite, .pollCreation, .pollUpdate,
			 .pollResultSnapshot, .reaction, .messageRevoked, .messageEdited, .messagePin, .messageKeep,
			 .newsletterAdminInvite, .newsletterFollowerInvite, .callLog, .stickerPack, .messageHistoryBundle, .album, .order, .product, .list,
			 .buttons, .interactive, .buttonsResponse, .listResponse, .templateButtonReply, .interactiveResponse,
			 .statusNotification, .statusQuestionAnswer, .statusQuoted, .statusStickerInteraction, .questionResponse,
			 .messageHistoryNotice, .aiRichResponse, .declinePaymentRequest, .cancelPaymentRequest, .paymentInvite, .placeholder,
			 .businessCall, .stickerSyncRMR, .encryptedComment, .encryptedReaction, .secretEncrypted, .comment, .sendPayment,
			 .requestPayment, .invoice:
			return true
		case .appStateSyncKeyShare, .appStateSyncKeyRequest, .lidMigrationMappingSync,
			 .historySyncNotification, .peerDataOperationRequestResponse, .stub:
			return false
		}
	}

	public func mediaDownloadRequest() throws -> MediaDownloadRequest? {
		switch self {
		case .text, .textLinkPreview, .location, .liveLocation, .event, .encryptedEventResponse, .scheduledCallCreation, .scheduledCallEdit, .contact, .contacts, .requestPhoneNumber, .ephemeralSetting, .phoneNumberShared, .limitSharing, .appStateSyncKeyShare, .appStateSyncKeyRequest, .lidMigrationMappingSync, .groupMemberLabelChange, .peerDataOperationRequestResponse, .highlyStructured, .groupInvite, .pollCreation, .pollUpdate, .pollResultSnapshot, .reaction, .messageRevoked, .messageEdited, .messagePin, .messageKeep, .newsletterAdminInvite, .newsletterFollowerInvite, .callLog, .album, .order, .product, .list, .buttons, .interactive, .buttonsResponse, .listResponse, .templateButtonReply, .interactiveResponse, .statusNotification, .statusQuestionAnswer, .statusQuoted, .statusStickerInteraction, .questionResponse, .messageHistoryNotice, .aiRichResponse, .declinePaymentRequest, .cancelPaymentRequest, .paymentInvite, .placeholder, .businessCall, .call, .chat, .stickerSyncRMR, .encryptedComment, .encryptedReaction, .secretEncrypted, .comment, .stub:
			return nil
		case .historySyncNotification(let history):
			guard let directPath = history.directPath,
				  let mediaKey = history.mediaKey,
				  let fileEncSHA256 = history.fileEncSHA256,
				  let fileSHA256 = history.fileSHA256 else {
				return nil
			}

			guard let url = MediaDirectPathURLResolver.url(from: directPath) else {
				throw ReceivedMessageContentParserError.invalidMediaURL
			}

			return MediaDownloadRequest(
				url: url,
				mediaKey: mediaKey,
				mediaType: .mdMessageHistory,
				fileEncSHA256: fileEncSHA256,
				fileSHA256: fileSHA256
			)
		case .image(let image):
			return MediaDownloadRequest(
				url: try mediaURL(url: image.url, directPath: image.directPath),
				mediaKey: image.mediaKey,
				mediaType: .image,
				fileEncSHA256: image.fileEncSHA256,
				fileSHA256: image.fileSHA256
			)
		case .document(let document):
			return MediaDownloadRequest(
				url: try mediaURL(url: document.url, directPath: document.directPath),
				mediaKey: document.mediaKey,
				mediaType: .document,
				fileEncSHA256: document.fileEncSHA256,
				fileSHA256: document.fileSHA256
			)
		case .audio(let audio):
			return MediaDownloadRequest(
				url: try mediaURL(url: audio.url, directPath: audio.directPath),
				mediaKey: audio.mediaKey,
				mediaType: .audio,
				fileEncSHA256: audio.fileEncSHA256,
				fileSHA256: audio.fileSHA256
			)
		case .video(let video):
			return MediaDownloadRequest(
				url: try mediaURL(url: video.url, directPath: video.directPath),
				mediaKey: video.mediaKey,
				mediaType: .video,
				fileEncSHA256: video.fileEncSHA256,
				fileSHA256: video.fileSHA256
			)
		case .sticker(let sticker):
			return MediaDownloadRequest(
				url: try mediaURL(url: sticker.url, directPath: sticker.directPath),
				mediaKey: sticker.mediaKey,
				mediaType: .sticker,
				fileEncSHA256: sticker.fileEncSHA256,
				fileSHA256: sticker.fileSHA256
			)
		case .stickerPack(let stickerPack):
			guard let directPath = stickerPack.thumbnailDirectPath,
				  let mediaKey = stickerPack.mediaKey,
				  let fileEncSHA256 = stickerPack.thumbnailEncSHA256,
				  let fileSHA256 = stickerPack.thumbnailSHA256 else {
				return nil
			}

			return MediaDownloadRequest(
				url: try mediaURL(url: "", directPath: directPath),
				mediaKey: mediaKey,
				mediaType: .thumbnailImage,
				fileEncSHA256: fileEncSHA256,
				fileSHA256: fileSHA256
			)
		case .messageHistoryBundle(let bundle):
			guard let directPath = bundle.directPath,
				  let mediaKey = bundle.mediaKey,
				  let fileEncSHA256 = bundle.fileEncSHA256,
				  let fileSHA256 = bundle.fileSHA256 else {
				return nil
			}

			guard let url = MediaDirectPathURLResolver.url(from: directPath) else {
				throw ReceivedMessageContentParserError.invalidMediaURL
			}

			return MediaDownloadRequest(
				url: url,
				mediaKey: mediaKey,
				mediaType: .mdMessageHistory,
				fileEncSHA256: fileEncSHA256,
				fileSHA256: fileSHA256
			)
		case .invoice(let invoice):
			guard let directPath = invoice.attachmentDirectPath,
				  let mediaKey = invoice.attachmentMediaKey,
				  let fileEncSHA256 = invoice.attachmentFileEncSHA256,
				  let fileSHA256 = invoice.attachmentFileSHA256,
				  let mediaType = invoice.attachmentType?.mediaType else {
				return nil
			}

			return MediaDownloadRequest(
				url: try mediaURL(url: "", directPath: directPath),
				mediaKey: mediaKey,
				mediaType: mediaType,
				fileEncSHA256: fileEncSHA256,
				fileSHA256: fileSHA256
			)
		case .requestPayment(let payment):
			return try payment.background?.mediaDownloadRequest()
		case .sendPayment(let payment):
			return try payment.background?.mediaDownloadRequest()
		}
	}

	private func mediaURL(url: String, directPath: String) throws -> URL {
		if !directPath.isEmpty {
			let host = URL(string: url)?.host ?? MediaDirectPathURLResolver.defaultHost
			if let parsedURL = MediaDirectPathURLResolver.url(from: directPath, host: host) {
				return parsedURL
			}
		}

		guard !url.isEmpty,
			  let parsedURL = URL(string: url),
			  parsedURL.scheme != nil else {
			throw ReceivedMessageContentParserError.invalidMediaURL
		}

		return parsedURL
	}
}

private extension ReceivedPaymentBackgroundContent {
	func mediaDownloadRequest() throws -> MediaDownloadRequest? {
		guard let mediaData,
			  let directPath = mediaData.directPath,
			  let mediaKey = mediaData.mediaKey,
			  let fileEncSHA256 = mediaData.fileEncSHA256,
			  let fileSHA256 = mediaData.fileSHA256 else {
			return nil
		}

		guard let url = MediaDirectPathURLResolver.url(from: directPath) else {
			throw ReceivedMessageContentParserError.invalidMediaURL
		}

		return MediaDownloadRequest(
			url: url,
			mediaKey: mediaKey,
			mediaType: .image,
			fileEncSHA256: fileEncSHA256,
			fileSHA256: fileSHA256
		)
	}
}

private extension ReceivedInvoiceAttachmentType {
	var mediaType: MediaType? {
		switch self {
		case .image:
			return .image
		case .pdf:
			return .document
		case .unrecognized:
			return nil
		}
	}
}

public enum ReceivedMessageContentParserError: Error, Equatable, Sendable {
	case invalidMediaURL
}
