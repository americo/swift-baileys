import Foundation

public struct BaileysStarMessage: Equatable, Sendable {
	public let id: String
	public let fromMe: Bool

	public init(id: String, fromMe: Bool = false) {
		self.id = id
		self.fromMe = fromMe
	}
}

public struct BaileysLabelAction: Equatable, Sendable {
	public let id: String
	public let name: String?
	public let color: Int32?
	public let predefinedID: Int32?
	public let deleted: Bool?

	public init(
		id: String,
		name: String? = nil,
		color: Int32? = nil,
		predefinedID: Int32? = nil,
		deleted: Bool? = nil
	) {
		self.id = id
		self.name = name
		self.color = color
		self.predefinedID = predefinedID
		self.deleted = deleted
	}
}

public struct BaileysQuickReplyAction: Equatable, Sendable {
	public let timestamp: String?
	public let shortcut: String
	public let message: String
	public let deleted: Bool

	public init(
		timestamp: String? = nil,
		shortcut: String = "",
		message: String = "",
		deleted: Bool = false
	) {
		self.timestamp = timestamp
		self.shortcut = shortcut
		self.message = message
		self.deleted = deleted
	}
}

extension WhatsAppClient {
	public func muteChat(_ jid: String, until muteEndTimestamp: Int64, requestID: String? = nil) async throws {
		try await chatModify(.mute(jid: jid, muteEndTimestamp: muteEndTimestamp), requestID: requestID)
	}

	public func unmuteChat(_ jid: String, requestID: String? = nil) async throws {
		try await chatModify(.mute(jid: jid, muteEndTimestamp: nil), requestID: requestID)
	}

	public func archiveChat(
		_ jid: String,
		archived: Bool,
		messageRange: AppStateChatMessageRange,
		requestID: String? = nil
	) async throws {
		try await chatModify(.archive(
			jid: jid,
			archived: archived,
			messageRange: try messageRange.proto()
		), requestID: requestID)
	}

	public func markChatRead(
		_ jid: String,
		read: Bool,
		messageRange: AppStateChatMessageRange,
		requestID: String? = nil
	) async throws {
		try await chatModify(.markRead(
			jid: jid,
			read: read,
			messageRange: try messageRange.proto()
		), requestID: requestID)
	}

	public func clearChat(
		_ jid: String,
		messageRange: AppStateChatMessageRange,
		requestID: String? = nil
	) async throws {
		try await chatModify(.clear(
			jid: jid,
			messageRange: try messageRange.proto()
		), requestID: requestID)
	}

	public func pinChat(_ jid: String, pinned: Bool, requestID: String? = nil) async throws {
		try await chatModify(.pin(jid: jid, pinned: pinned), requestID: requestID)
	}

	public func updatePushNameSetting(_ name: String, requestID: String? = nil) async throws {
		try await chatModify(.pushNameSetting(name), requestID: requestID)
	}

	public func updateDisableLinkPreviewsPrivacy(_ isPreviewsDisabled: Bool, requestID: String? = nil) async throws {
		try await chatModify(.disableLinkPreviews(isPreviewsDisabled: isPreviewsDisabled), requestID: requestID)
	}

	public func addOrEditContact(
		_ jid: String,
		fullName: String? = nil,
		firstName: String? = nil,
		lidJid: String? = nil,
		saveOnPrimaryAddressbook: Bool? = nil,
		pnJid: String? = nil,
		username: String? = nil,
		requestID: String? = nil
	) async throws {
		try await chatModify(.contact(
			jid: jid,
			contact: ChatModificationContact(
				fullName: fullName,
				firstName: firstName,
				lidJid: lidJid,
				saveOnPrimaryAddressbook: saveOnPrimaryAddressbook,
				pnJid: pnJid,
				username: username
			)
		), requestID: requestID)
	}

	public func removeContact(_ jid: String, requestID: String? = nil) async throws {
		try await chatModify(.contact(jid: jid, contact: nil), requestID: requestID)
	}

	public func starMessage(
		jid: String,
		messageID: String,
		fromMe: Bool,
		starred: Bool,
		requestID: String? = nil
	) async throws {
		try await chatModify(.star(
			jid: jid,
			messageID: messageID,
			fromMe: fromMe,
			starred: starred
		), requestID: requestID)
	}

	public func star(
		jid: String,
		messages: [BaileysStarMessage],
		starred: Bool,
		requestID: String? = nil
	) async throws {
		guard let message = messages.first else {
			throw WhatsAppClientError.missingReceiptMessageIDs
		}

		try await starMessage(
			jid: jid,
			messageID: message.id,
			fromMe: message.fromMe,
			starred: starred,
			requestID: requestID
		)
	}

	public func deleteChat(
		_ jid: String,
		messageRange: AppStateChatMessageRange,
		requestID: String? = nil
	) async throws {
		try await chatModify(.deleteChat(
			jid: jid,
			messageRange: try messageRange.proto()
		), requestID: requestID)
	}

	public func deleteMessageForMe(
		jid: String,
		messageID: String,
		fromMe: Bool,
		timestamp: Int64,
		deleteMedia: Bool,
		requestID: String? = nil
	) async throws {
		try await chatModify(.deleteForMe(
			jid: jid,
			messageID: messageID,
			fromMe: fromMe,
			timestamp: timestamp,
			deleteMedia: deleteMedia
		), requestID: requestID)
	}

	public func setQuickReply(
		timestamp: String,
		shortcut: String,
		message: String,
		requestID: String? = nil
	) async throws {
		try await chatModify(.quickReply(
			timestamp: timestamp,
			shortcut: shortcut,
			message: message,
			deleted: false
		), requestID: requestID)
	}

	public func deleteQuickReply(
		timestamp: String,
		shortcut: String,
		message: String,
		requestID: String? = nil
	) async throws {
		try await chatModify(.quickReply(
			timestamp: timestamp,
			shortcut: shortcut,
			message: message,
			deleted: true
		), requestID: requestID)
	}

	public func addOrEditQuickReply(
		_ quickReply: BaileysQuickReplyAction,
		requestID: String? = nil
	) async throws {
		let timestamp = quickReply.timestamp ?? String(Int(Date().timeIntervalSince1970))
		try await chatModify(.quickReply(
			timestamp: timestamp,
			shortcut: quickReply.shortcut,
			message: quickReply.message,
			deleted: quickReply.deleted
		), requestID: requestID)
	}

	public func removeQuickReply(timestamp: String, requestID: String? = nil) async throws {
		try await addOrEditQuickReply(
			BaileysQuickReplyAction(timestamp: timestamp, deleted: true),
			requestID: requestID
		)
	}

	public func editLabel(
		id: String,
		name: String? = nil,
		color: Int32? = nil,
		predefinedID: Int32? = nil,
		deleted: Bool? = nil,
		requestID: String? = nil
	) async throws {
		try await chatModify(.labelEdit(
			id: id,
			name: name,
			color: color,
			predefinedID: predefinedID,
			deleted: deleted
		), requestID: requestID)
	}

	public func addLabel(
		jid: String,
		labels: BaileysLabelAction,
		requestID: String? = nil
	) async throws {
		try await editLabel(
			id: labels.id,
			name: labels.name,
			color: labels.color,
			predefinedID: labels.predefinedID,
			deleted: labels.deleted,
			requestID: requestID
		)
	}

	public func deleteLabel(id: String, requestID: String? = nil) async throws {
		try await editLabel(id: id, deleted: true, requestID: requestID)
	}

	public func addChatLabel(jid: String, labelID: String, requestID: String? = nil) async throws {
		try await chatModify(.chatLabel(jid: jid, labelID: labelID, labeled: true), requestID: requestID)
	}

	public func removeChatLabel(jid: String, labelID: String, requestID: String? = nil) async throws {
		try await chatModify(.chatLabel(jid: jid, labelID: labelID, labeled: false), requestID: requestID)
	}

	public func addMessageLabel(
		jid: String,
		messageID: String,
		labelID: String,
		requestID: String? = nil
	) async throws {
		try await chatModify(.messageLabel(
			jid: jid,
			messageID: messageID,
			labelID: labelID,
			labeled: true
		), requestID: requestID)
	}

	public func removeMessageLabel(
		jid: String,
		messageID: String,
		labelID: String,
		requestID: String? = nil
	) async throws {
		try await chatModify(.messageLabel(
			jid: jid,
			messageID: messageID,
			labelID: labelID,
			labeled: false
		), requestID: requestID)
	}

	func chatModify(_ modification: ChatModification, requestID: String? = nil) async throws {
		_ = try await appPatch(
			ChatModificationPatchBuilder.patch(for: modification),
			requestID: requestID,
			keyExpander: appStateKeyExpander ?? NativeAppStateKeyExpander(),
			hashMixer: appStateHashMixer ?? NativeAppStatePatchHashMixer(),
			randomBytes: appStateRandomBytes ?? MessageIDGenerator.secureRandomBytes(count:)
		)
	}

	func appPatch(
		_ patch: ChatModificationPatch,
		requestID: String? = nil,
		keyExpander: any AppStateKeyExpanding,
		hashMixer: any AppStatePatchHashMixing,
		randomBytes: @escaping @Sendable (Int) throws -> Data = MessageIDGenerator.secureRandomBytes(count:)
	) async throws -> AppStatePatchState {
		guard let authenticationState else {
			throw WhatsAppClientError.missingAuthenticationState
		}
		guard let appStateKeyID = authenticationState.credentials.myAppStateKeyID else {
			throw WhatsAppClientError.missingAppStateKeyID
		}
		guard let keyID = Data(base64Encoded: appStateKeyID) else {
			throw WhatsAppClientError.invalidAppStateKeyID
		}

		let keyEntries = try await authenticationState.keys.get(.appStateSyncKey, ids: [appStateKeyID])
		guard let keyDataBytes = keyEntries[appStateKeyID] else {
			throw WhatsAppClientError.missingAppStateSyncKey
		}
		let keyData = try Proto_Message.AppStateSyncKeyData(serializedBytes: keyDataBytes)
		let keys = try keyExpander.expand(keyData: keyData.keyData)
		let storedStates = try await authenticationState.keys.get(.appStateSyncVersion, ids: [patch.type.rawValue])
		let initialState: AppStatePatchState
		if let storedState = storedStates[patch.type.rawValue] {
			initialState = try JSONDecoder().decode(AppStatePatchState.self, from: storedState)
		} else {
			initialState = AppStatePatchState()
		}

		let encodingResult = try AppStatePatchEncoder.encode(
			patch,
			keyID: keyID,
			keys: keys,
			state: initialState,
			randomBytes: randomBytes,
			hashMixer: hashMixer
		)
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState.credentials.me?.id)
		let node = try AppStatePatchNodeBuilder.syncIQ(for: patch.type, encodingResult: encodingResult, requestID: id)
		_ = try await query(node)
		try await authenticationState.keys.set([
			.appStateSyncVersion: [patch.type.rawValue: try JSONEncoder().encode(encodingResult.state)]
		])
		return encodingResult.state
	}
}
