import Foundation

public struct AppStateSyncResult: Equatable, Sendable {
	public let collectionVersions: [String: UInt64]
	public let hasMorePatches: [String: Bool]
	public let decodedMutationCount: Int
	public let invalidSnapshotMACCollections: [String]
}

public extension WhatsAppClient {
	func storeAppStateSyncKeys(_ share: ReceivedAppStateSyncKeyShareContent) async throws {
		guard let authenticationState else {
			throw WhatsAppClientError.missingAuthenticationState
		}

		var storedKeys: [String: Data?] = [:]
		for key in share.keys {
			guard let keyID = key.keyIDBase64 ?? key.keyID?.base64EncodedString(),
				  let rawKeyData = key.keyData else {
				continue
			}

			var keyData = Proto_Message.AppStateSyncKeyData()
			keyData.keyData = rawKeyData
			if let fingerprint = key.fingerprint {
				var protoFingerprint = Proto_Message.AppStateSyncKeyFingerprint()
				if let rawID = fingerprint.rawID {
					protoFingerprint.rawID = rawID
				}
				if let currentIndex = fingerprint.currentIndex {
					protoFingerprint.currentIndex = currentIndex
				}
				protoFingerprint.deviceIndexes = fingerprint.deviceIndexes
				keyData.fingerprint = protoFingerprint
			}
			if let timestamp = key.timestamp {
				keyData.timestamp = timestamp
			}
			storedKeys[keyID] = try keyData.serializedData()
		}

		if !storedKeys.isEmpty {
			try await authenticationState.keys.set([.appStateSyncKey: storedKeys])
			// New patches are encrypted with the most recent key the phone shared.
			if let latestKeyID = latestAppStateKeyID(in: share) {
				try await updateCredentials { credentials in
					credentials.myAppStateKeyID = latestKeyID
				}
			}
			retryBlockedAppStateSyncCollections()
		}
	}

	@discardableResult
	func requestAppStateSync(
		collections: [AppStateCollectionName] = AppStateCollectionName.allCases,
		forceSnapshot: Bool = false,
		forceSnapshotCollections: Set<AppStateCollectionName> = [],
		requestID: String? = nil
	) async throws -> BinaryNode {
		guard let authenticationState else {
			throw WhatsAppClientError.missingAuthenticationState
		}

		let ids = collections.map(\.rawValue)
		let storedStates = try await authenticationState.keys.get(.appStateSyncVersion, ids: ids)
		let requests = try collections.map { collection in
			let version: UInt64
			if let storedState = storedStates[collection.rawValue] {
				version = try JSONDecoder().decode(AppStatePatchState.self, from: storedState).version
			} else {
				version = 0
			}

			return AppStateSyncCollectionRequest(
				name: collection,
				version: version,
				returnSnapshot: forceSnapshot || forceSnapshotCollections.contains(collection) || version == 0
			)
		}
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState.credentials.me?.id)
		let node = try AppStateSyncRequestNodeBuilder.syncIQ(collections: requests, requestID: id)
		return try await query(node)
	}

	/// Fetches app-state patches (contacts, pins, mutes, ...) and emits the resulting events.
	/// Needs `configureAppStateDependencies` and the sync keys shared by the primary phone.
	@discardableResult
	public func resyncAppState(
		collections: [AppStateCollectionName] = AppStateCollectionName.allCases,
		forceSnapshot: Bool = false
	) async throws -> AppStateSyncResult {
		try await syncAppState(collections: collections, forceSnapshot: forceSnapshot)
	}

	func syncAppState(
		collections: [AppStateCollectionName] = AppStateCollectionName.allCases,
		forceSnapshot: Bool = false
	) async throws -> AppStateSyncResult {
		try await serializeAppStateWork { [self] in
			try await syncAppState(
				collections: collections,
				forceSnapshot: forceSnapshot,
				downloadExternalBlob: appStateExternalBlobDownloader()
			)
		}
	}
}

enum AppStateExternalBlobDownloadError: Error, Equatable, Sendable {
	case missingMediaKey
	case missingDirectPath
	case missingFileSHA256
	case missingFileEncSHA256
	case invalidURL(String)
}

func appStateExternalBlobDownloadRequest(_ reference: Proto_ExternalBlobReference) throws -> MediaDownloadRequest {
	guard reference.hasMediaKey else {
		throw AppStateExternalBlobDownloadError.missingMediaKey
	}
	guard reference.hasDirectPath else {
		throw AppStateExternalBlobDownloadError.missingDirectPath
	}
	guard reference.hasFileSha256 else {
		throw AppStateExternalBlobDownloadError.missingFileSHA256
	}
	guard reference.hasFileEncSha256 else {
		throw AppStateExternalBlobDownloadError.missingFileEncSHA256
	}
	guard let url = MediaDirectPathURLResolver.url(from: reference.directPath) else {
		throw AppStateExternalBlobDownloadError.invalidURL(reference.directPath)
	}

	return MediaDownloadRequest(
		url: url,
		mediaKey: reference.mediaKey,
		mediaType: .mdAppState,
		fileEncSHA256: reference.fileEncSha256,
		fileSHA256: reference.fileSha256
	)
}

extension WhatsAppClient {
	func appStateExternalBlobDownloader() -> AppStateExternalBlobDownloader {
		{ [mediaDownloader] reference in
			try await mediaDownloader.download(appStateExternalBlobDownloadRequest(reference))
		}
	}

	/// Syncs and patches both build on a collection's stored version, so they run one at a time.
	func serializeAppStateWork<T: Sendable>(
		_ work: @escaping @Sendable () async throws -> T
	) async throws -> T {
		let previous = appStateWorkTail
		let task = Task<T, any Error> {
			await previous?.value
			return try await work()
		}
		appStateWorkTail = Task { _ = await task.result }
		return try await task.value
	}

	/// Accounts linked before the key id was recorded still hold the keys the phone shared.
	/// Picks the most recent of them. Returns whether a key id is known afterwards.
	@discardableResult
	public func adoptStoredAppStateKey(ids: [String]) async throws -> Bool {
		guard let authenticationState else {
			throw WhatsAppClientError.missingAuthenticationState
		}
		if authenticationState.credentials.myAppStateKeyID != nil {
			return true
		}
		let stored = try await authenticationState.keys.get(.appStateSyncKey, ids: ids)
		var latest: (id: String, timestamp: Int64)?
		for (id, data) in stored {
			guard Data(base64Encoded: id) != nil,
				  let key = try? Proto_Message.AppStateSyncKeyData(serializedBytes: data) else {
				continue
			}
			if key.timestamp >= (latest?.timestamp ?? .min) {
				latest = (id, key.timestamp)
			}
		}
		guard let latest else {
			return false
		}
		try await updateCredentials { credentials in
			credentials.myAppStateKeyID = latest.id
		}
		return true
	}

	func requestAppStateSyncKeys(ids: [Data]) async throws {
		guard !ids.isEmpty, let meJID = authenticationState?.credentials.me?.id else {
			return
		}
		var request = Proto_Message.AppStateSyncKeyRequest()
		request.keyIds = ids.map { id in
			var keyID = Proto_Message.AppStateSyncKeyId()
			keyID.keyID = id
			return keyID
		}
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.appStateSyncKeyRequest = request
		protocolMessage.type = .appStateSyncKeyRequest
		var message = Proto_Message()
		message.protocolMessage = protocolMessage
		_ = try await sendResolvedMessage(
			to: JID(meJID)?.normalizedUser ?? meJID,
			message: message,
			messageID: nil,
			additionalAttributes: ["category": "peer", "push_priority": "high_force"],
			additionalNodes: [BinaryNode(tag: "meta", attrs: ["appdata": "default"])]
		)
		WhatsAppLog.logger.notice("app state keys requested count=\(ids.count)")
	}

	private func latestAppStateKeyID(in share: ReceivedAppStateSyncKeyShareContent) -> String? {
		var latest: (id: String, timestamp: Int64)?
		for key in share.keys where key.keyData != nil {
			guard let id = key.keyIDBase64 ?? key.keyID?.base64EncodedString() else {
				continue
			}
			let timestamp = key.timestamp ?? 0
			if timestamp >= (latest?.timestamp ?? .min) {
				latest = (id, timestamp)
			}
		}
		return latest?.id
	}

	/// Accounts linked before the key id was recorded only learn it from what the server sends.
	private func rememberAppStateKeyIDIfMissing(_ keyID: Data?) async throws {
		guard authenticationState?.credentials.myAppStateKeyID == nil,
			  let keyID, !keyID.isEmpty else {
			return
		}
		try await updateCredentials { credentials in
			credentials.myAppStateKeyID = keyID.base64EncodedString()
		}
	}

	func syncAppState(
		collections: [AppStateCollectionName],
		forceSnapshot: Bool,
		downloadExternalBlob: AppStateExternalBlobDownloader?
	) async throws -> AppStateSyncResult {
		guard let authenticationState else {
			throw WhatsAppClientError.missingAuthenticationState
		}

		var pending = Set(collections)
		var versions: [String: UInt64] = [:]
		var hasMorePatches: [String: Bool] = [:]
		var decodedMutationCount = 0
		var invalidSnapshotMACCollections: [String] = []
		var attempts: [AppStateCollectionName: Int] = [:]
		var forceSnapshotCollections = Set<AppStateCollectionName>()
		var missingKeyIDs = Set<String>()

		while !pending.isEmpty {
			let requestedCollections = collections.filter { pending.contains($0) }
			let result = try await requestAppStateSync(
				collections: requestedCollections,
				forceSnapshot: forceSnapshot && versions.isEmpty,
				forceSnapshotCollections: forceSnapshotCollections
			)
			for node in result.firstChild(named: "sync")?.children(named: "collection") ?? [] {
				let error = node.firstChild(named: "error")?.attrs["code"] ?? "-"
				let children = node.children(named: "patches").count + node.children(named: "patch").count
				WhatsAppLog.logger.notice("app state answer \(node.attrs["name"] ?? "?", privacy: .public) version=\(node.attrs["version"] ?? "-", privacy: .public) type=\(node.attrs["type"] ?? "-", privacy: .public) error=\(error, privacy: .public) snapshot=\(node.firstChild(named: "snapshot") != nil) patches=\(children)")
			}
			let extracted = try await AppStateSyncExtractor.extract(
				from: result,
				downloadExternalBlob: downloadExternalBlob
			)

			for collection in requestedCollections {
				guard let syncCollection = extracted[collection.rawValue] else {
					pending.remove(collection)
					continue
				}

				var state = try await appStatePatchState(for: collection.rawValue, keys: authenticationState.keys)
				do {
					if let snapshot = syncCollection.snapshot {
						let decodedSnapshot = try await AppStateSnapshotDecoder.decode(
							snapshot,
							collection: collection,
							keyResolver: appStateKeyResolver(keys: authenticationState.keys),
							hashMixer: NativeAppStatePatchHashMixer()
						)
						state = decodedSnapshot.state
						decodedMutationCount += decodedSnapshot.mutations.count
						try await emitAppStateMutationEvents(decodedSnapshot.mutations, fromSnapshot: true)
						try await rememberAppStateKeyIDIfMissing(snapshot.keyID.id)
						if !decodedSnapshot.snapshotMACValid {
							invalidSnapshotMACCollections.append(collection.rawValue)
						}
					}

					for patch in syncCollection.patches {
						let decodedPatch = try await AppStatePatchDecoder.decode(
							patch,
							collection: collection,
							initialState: state,
							keyResolver: appStateKeyResolver(keys: authenticationState.keys),
							hashMixer: NativeAppStatePatchHashMixer(),
							downloadExternalBlob: downloadExternalBlob
						)
						state = decodedPatch.state
						decodedMutationCount += decodedPatch.mutations.count
						try await emitAppStateMutationEvents(decodedPatch.mutations)
						try await rememberAppStateKeyIDIfMissing(patch.keyID.id)
					}
				} catch {
					WhatsAppLog.logger.error("app state \(collection.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
					if let keyID = AppStateSyncErrorPolicy.missingKeyID(error) {
						missingKeyIDs.insert(keyID)
					}
					let attempt = (attempts[collection] ?? 0) + 1
					attempts[collection] = attempt
					if AppStateSyncErrorPolicy.isMissingKey(error) {
						if AppStateSyncErrorPolicy.isIrrecoverable(attempts: attempt) {
							blockedAppStateSyncCollections.insert(collection)
							pending.remove(collection)
						} else {
							forceSnapshotCollections.insert(collection)
						}
						continue
					}
					if AppStateSyncErrorPolicy.isIrrecoverable(attempts: attempt) {
						pending.remove(collection)
					} else {
						forceSnapshotCollections.insert(collection)
					}
					continue
				}

				try await authenticationState.keys.set([
					.appStateSyncVersion: [collection.rawValue: try JSONEncoder().encode(state)]
				])
				versions[collection.rawValue] = state.version
				attempts[collection] = nil
				forceSnapshotCollections.remove(collection)
				hasMorePatches[collection.rawValue] = syncCollection.hasMorePatches
				if !syncCollection.hasMorePatches {
					pending.remove(collection)
				}
			}
		}

		if !missingKeyIDs.isEmpty {
			// The share sent while linking can be lost. The phone's answer resumes blocked collections.
			do {
				try await requestAppStateSyncKeys(ids: missingKeyIDs.compactMap { Data(base64Encoded: $0) })
			} catch {
				WhatsAppLog.logger.error("app state key request failed: \(String(describing: error), privacy: .public)")
			}
		}

		return AppStateSyncResult(
			collectionVersions: versions,
			hasMorePatches: hasMorePatches,
			decodedMutationCount: decodedMutationCount,
			invalidSnapshotMACCollections: invalidSnapshotMACCollections
		)
	}

	private func retryBlockedAppStateSyncCollections() {
		let collections = Array(blockedAppStateSyncCollections)
		guard !collections.isEmpty else {
			return
		}

		blockedAppStateSyncCollections.removeAll()
		Task {
			try? await syncAppState(collections: collections)
		}
	}

	/// A snapshot holds the last action of every index, however old. Replaying a deletion or a
	/// "read" from it could hit messages and unread counts that arrived after that action.
	private func emitAppStateMutationEvents(
		_ mutations: [AppStateDecodedMutation],
		fromSnapshot: Bool = false
	) async throws {
		for mutation in mutations {
			let action = mutation.syncAction.value
			if action.hasMuteAction, mutation.index.count > 1 {
				let mute = action.muteAction
				eventContinuation.yield(.chatsUpdated([
					ChatUpdate(
						id: mutation.index[1],
						muteEndTime: mute.muted ? mute.muteEndTimestamp : nil,
						isMuted: mute.muted
					)
				]))
			} else if (action.hasArchiveChatAction || mutation.index.first == "archive" || mutation.index.first == "unarchive"),
					  mutation.index.count > 1 {
				eventContinuation.yield(.chatsUpdated([
					ChatUpdate(
						id: mutation.index[1],
						archived: action.hasArchiveChatAction ? action.archiveChatAction.archived : mutation.index[0] == "archive"
					)
				]))
			} else if action.hasMarkChatAsReadAction, mutation.index.count > 1 {
				if fromSnapshot, action.markChatAsReadAction.read {
					continue
				}
				eventContinuation.yield(.chatsUpdated([
					ChatUpdate(id: mutation.index[1], unreadCount: action.markChatAsReadAction.read ? 0 : -1)
				]))
			} else if action.hasPinAction, mutation.index.count > 1 {
				eventContinuation.yield(.chatsUpdated([
					ChatUpdate(
						id: mutation.index[1],
						pinned: action.pinAction.pinned ? action.timestamp : nil,
						isPinned: action.pinAction.pinned
					)
				]))
			} else if (action.hasDeleteMessageForMeAction || mutation.index.first == "deleteMessageForMe"),
					  mutation.index.count > 3 {
				if fromSnapshot {
					continue
				}
				eventContinuation.yield(.messagesDeleted(MessageDeleteUpdate(keys: [
					WhatsAppMessageKey(
						remoteJID: mutation.index[1],
						fromMe: mutation.index[3] == "1",
						id: mutation.index[2]
					)
				])))
			} else if (action.hasStarAction || mutation.index.first == "star"),
					  mutation.index.count > 3 {
				eventContinuation.yield(.messagesUpdated([
					ReceivedMessageUpdate(
						key: WhatsAppMessageKey(
							remoteJID: mutation.index[1],
							fromMe: mutation.index[3] == "1",
							id: mutation.index[2]
						),
						status: nil,
						timestamp: nil,
						starred: action.hasStarAction ? action.starAction.starred : mutation.index[mutation.index.count - 1] == "1"
					)
				]))
			} else if (action.hasDeleteChatAction || mutation.index.first == "deleteChat"),
					  mutation.index.count > 1 {
				if fromSnapshot {
					continue
				}
				eventContinuation.yield(.chatsDeleted(ChatDeleteUpdate(ids: [mutation.index[1]])))
			} else if action.hasContactAction, mutation.index.count > 1 {
				let contact = action.contactAction
				eventContinuation.yield(.contactsUpdated([
					ContactUpdate(
						id: mutation.index[1],
						name: contact.hasFullName ? contact.fullName : contact.hasFirstName ? contact.firstName : contact.hasUsername ? contact.username : nil,
						username: contact.hasUsername ? contact.username : nil,
						lid: contact.hasLidJid ? contact.lidJid : nil,
						phoneNumber: mutation.index[1].hasSuffix("@s.whatsapp.net") ? mutation.index[1] : contact.hasPnJid ? contact.pnJid : nil
					)
				]))
				if contact.hasLidJid,
				   contact.lidJid.hasSuffix("@lid"),
				   mutation.index[1].hasSuffix("@s.whatsapp.net") {
					let mapping = LIDMapping(pn: mutation.index[1], lid: contact.lidJid)
					try? await storeLIDMappings([mapping])
					eventContinuation.yield(.lidMappingUpdated(mapping))
				}
			} else if action.hasPnForLidChatAction, mutation.index.count > 1 {
				let mapping = action.pnForLidChatAction
				if mapping.hasPnJid {
					let lidMapping = LIDMapping(pn: mapping.pnJid, lid: mutation.index[1])
					try? await storeLIDMappings([lidMapping])
					eventContinuation.yield(.lidMappingUpdated(lidMapping))
				}
			} else if action.hasLockChatAction, mutation.index.count > 1 {
				eventContinuation.yield(.chatLockUpdated(ChatLockUpdate(
					id: mutation.index[1],
					locked: action.lockChatAction.locked
				)))
			} else if action.hasLidContactAction, mutation.index.count > 1 {
				let contact = action.lidContactAction
				eventContinuation.yield(.contactsUpdated([
					ContactUpdate(
						id: mutation.index[1],
						name: contact.hasFullName ? contact.fullName : contact.hasFirstName ? contact.firstName : contact.hasUsername ? contact.username : nil,
						username: contact.hasUsername ? contact.username : nil,
						lid: mutation.index[1]
					)
				]))
			} else if action.hasLabelEditAction, mutation.index.count > 1 {
				let edit = action.labelEditAction
				eventContinuation.yield(.labelEdited(LabelUpdate(
					id: mutation.index[1],
					name: edit.hasName ? edit.name : nil,
					color: edit.hasColor ? edit.color : nil,
					deleted: edit.hasDeleted ? edit.deleted : nil,
					predefinedID: edit.hasPredefinedID ? String(edit.predefinedID) : nil
				)))
			} else if action.hasLabelAssociationAction {
				emitLabelAssociationUpdate(index: mutation.index, action: action.labelAssociationAction)
			} else if action.hasStickerAction, mutation.index.count > 1 {
				let sticker = action.stickerAction
				eventContinuation.yield(.favoriteStickerUpdated(FavoriteStickerUpdate(
					sticker: FavoriteSticker(
						id: mutation.index[1],
						url: sticker.url,
						directPath: sticker.directPath,
						mediaKey: sticker.mediaKey,
						fileEncSHA256: sticker.fileEncSha256,
						mimetype: sticker.mimetype,
						width: sticker.width,
						height: sticker.height,
						fileLength: sticker.fileLength,
						isFavorite: sticker.isFavorite,
						isLottie: sticker.isLottie,
						isAvatarSticker: sticker.isAvatarSticker,
						timestamp: action.timestamp
					),
					removed: mutation.operation == .remove
				)))
			} else if action.hasPushNameSetting,
					  action.pushNameSetting.hasName,
					  authenticationState?.credentials.me?.name != action.pushNameSetting.name {
				try await updateCredentials { credentials in
					credentials.me?.name = action.pushNameSetting.name
				}
			} else if action.hasUnarchiveChatsSetting {
				try await updateCredentials { credentials in
					credentials.accountSettings.unarchiveChats = action.unarchiveChatsSetting.unarchiveChats
				}
			} else if action.hasLocaleSetting, action.localeSetting.hasLocale {
				eventContinuation.yield(.settingsUpdated(SettingsUpdate(
					setting: "locale",
					value: .string(action.localeSetting.locale)
				)))
			} else if action.hasTimeFormatAction {
				eventContinuation.yield(.settingsUpdated(SettingsUpdate(
					setting: "timeFormat",
					value: .bool(action.timeFormatAction.isTwentyFourHourFormatEnabled)
				)))
			} else if action.hasPrivacySettingRelayAllCalls {
				eventContinuation.yield(.settingsUpdated(SettingsUpdate(
					setting: "privacySettingRelayAllCalls",
					value: .bool(action.privacySettingRelayAllCalls.isEnabled)
				)))
			} else if action.hasStatusPrivacy {
				eventContinuation.yield(.settingsUpdated(SettingsUpdate(
					setting: "statusPrivacy",
					value: .statusPrivacy(StatusPrivacyUpdate(
						mode: action.statusPrivacy.mode.rawValue,
						userJIDs: action.statusPrivacy.userJid
					))
				)))
			} else if action.hasPrivacySettingDisableLinkPreviewsAction {
				eventContinuation.yield(.settingsUpdated(SettingsUpdate(
					setting: "disableLinkPreviews",
					value: .bool(action.privacySettingDisableLinkPreviewsAction.isPreviewsDisabled)
				)))
			} else if action.hasNotificationActivitySettingAction,
					  action.notificationActivitySettingAction.hasNotificationActivitySetting {
				eventContinuation.yield(.settingsUpdated(SettingsUpdate(
					setting: "notificationActivitySetting",
					value: .int(action.notificationActivitySettingAction.notificationActivitySetting.rawValue)
				)))
			} else if action.hasPrivacySettingChannelsPersonalisedRecommendationAction {
				eventContinuation.yield(.settingsUpdated(SettingsUpdate(
					setting: "channelsPersonalisedRecommendation",
					value: .bool(action.privacySettingChannelsPersonalisedRecommendationAction.isUserOptedOut)
				)))
			}
		}
	}

	private func emitLabelAssociationUpdate(index: [String], action: Proto_SyncActionValue.LabelAssociationAction) {
		let updateType: LabelAssociationUpdateType = action.labeled ? .add : .remove
		if index.first == "label_jid",
		   index.count > 2 {
			eventContinuation.yield(.labelAssociationUpdated(LabelAssociationUpdate(
				association: .chat(chatID: index[2], labelID: index[1]),
				type: updateType
			)))
		} else if index.first == "label_message",
				  index.count > 3 {
			eventContinuation.yield(.labelAssociationUpdated(LabelAssociationUpdate(
				association: .message(chatID: index[2], messageID: index[3], labelID: index[1]),
				type: updateType
			)))
		}
	}

}

private func appStatePatchState(for collection: String, keys: any SignalKeyStore) async throws -> AppStatePatchState {
	let storedStates = try await keys.get(.appStateSyncVersion, ids: [collection])
	guard let storedState = storedStates[collection] else {
		return AppStatePatchState()
	}

	return try JSONDecoder().decode(AppStatePatchState.self, from: storedState)
}

private func appStateKeyResolver(keys: any SignalKeyStore) -> AppStatePatchKeyResolver {
	{ keyID in
		let entries = try await keys.get(.appStateSyncKey, ids: [keyID])
		guard let data = entries[keyID] else {
			return nil
		}

		return try NativeAppStateKeyExpander().expand(keyData: Proto_Message.AppStateSyncKeyData(serializedBytes: data).keyData)
	}
}
