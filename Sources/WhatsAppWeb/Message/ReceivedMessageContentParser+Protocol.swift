extension ReceivedMessageContentParser {
	static func protocolContent(
		_ protocolMessage: Proto_Message.ProtocolMessageMessage
	) -> ReceivedMessageContent? {
		if protocolMessage.type == .revoke {
			return .messageRevoked(ReceivedMessageRevokedContent(
				key: protocolMessage.hasKey ? messageKey(protocolMessage.key) : nil,
				timestampMilliseconds: protocolMessage.hasTimestampMs ? protocolMessage.timestampMs : nil
			))
		}

		if protocolMessage.type == .messageEdit {
			return .messageEdited(ReceivedMessageEditedContent(
				key: protocolMessage.hasKey ? messageKey(protocolMessage.key) : nil,
				content: protocolMessage.hasEditedMessage ? parse(protocolMessage.editedMessage) : nil,
				timestampMilliseconds: protocolMessage.hasTimestampMs ? protocolMessage.timestampMs : nil
			))
		}

		if protocolMessage.type == .ephemeralSetting {
			return .ephemeralSetting(ephemeralSettingContent(protocolMessage))
		}

		if protocolMessage.type == .sharePhoneNumber {
			return .phoneNumberShared(ReceivedPhoneNumberSharedContent())
		}

		if protocolMessage.type == .limitSharing {
			return .limitSharing(limitSharingContent(protocolMessage.limitSharing))
		}

		if protocolMessage.type == .appStateSyncKeyShare {
			return .appStateSyncKeyShare(appStateSyncKeyShareContent(protocolMessage.appStateSyncKeyShare))
		}

		if protocolMessage.type == .appStateSyncKeyRequest {
			return .appStateSyncKeyRequest(appStateSyncKeyRequestContent(protocolMessage.appStateSyncKeyRequest))
		}

		if protocolMessage.type == .lidMigrationMappingSync {
			return .lidMigrationMappingSync(lidMigrationMappingSyncContent(protocolMessage.lidMigrationMappingSyncMessage))
		}

		if protocolMessage.type == .groupMemberLabelChange {
			return .groupMemberLabelChange(groupMemberLabelChangeContent(protocolMessage.memberLabel))
		}

		if protocolMessage.type == .historySyncNotification {
			return .historySyncNotification(historySyncNotificationContent(protocolMessage.historySyncNotification))
		}

		if protocolMessage.type == .peerDataOperationRequestResponseMessage {
			return .peerDataOperationRequestResponse(
				peerDataOperationRequestResponseContent(protocolMessage.peerDataOperationRequestResponseMessage)
			)
		}

		return nil
	}

	static func ephemeralSettingContent(
		_ protocolMessage: Proto_Message.ProtocolMessageMessage
	) -> ReceivedEphemeralSettingContent {
		ReceivedEphemeralSettingContent(
			expirationSeconds: protocolMessage.hasEphemeralExpiration ? protocolMessage.ephemeralExpiration : nil,
			settingTimestampSeconds: protocolMessage.hasEphemeralSettingTimestamp
				? protocolMessage.ephemeralSettingTimestamp
				: nil,
			disappearingMode: protocolMessage.hasDisappearingMode
				? disappearingModeContent(protocolMessage.disappearingMode)
				: nil
		)
	}

	private static func disappearingModeContent(
		_ mode: Proto_DisappearingMode
	) -> ReceivedDisappearingModeContent {
		ReceivedDisappearingModeContent(
			initiator: mode.hasInitiator ? disappearingModeInitiator(mode.initiator) : nil,
			trigger: mode.hasTrigger ? disappearingModeTrigger(mode.trigger) : nil,
			initiatorDeviceJID: mode.hasInitiatorDeviceJid ? mode.initiatorDeviceJid : nil,
			initiatedByMe: mode.hasInitiatedByMe ? mode.initiatedByMe : nil
		)
	}

	private static func disappearingModeInitiator(
		_ initiator: Proto_DisappearingMode.Initiator
	) -> ReceivedDisappearingModeInitiator {
		switch initiator {
		case .changedInChat:
			.changedInChat
		case .initiatedByMe:
			.initiatedByMe
		case .initiatedByOther:
			.initiatedByOther
		case .bizUpgradeFbHosting:
			.businessUpgradeFBHosting
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	private static func disappearingModeTrigger(
		_ trigger: Proto_DisappearingMode.Trigger
	) -> ReceivedDisappearingModeTrigger {
		switch trigger {
		case .unknown:
			.unknown
		case .chatSetting:
			.chatSetting
		case .accountSetting:
			.accountSetting
		case .bulkChange:
			.bulkChange
		case .bizSupportsFbHosting:
			.bizSupportsFBHosting
		case .unknownGroups:
			.unknownGroups
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	static func historySyncNotificationContent(
		_ notification: Proto_Message.HistorySyncNotification
	) -> ReceivedHistorySyncNotificationContent {
		let accessStatus = notification.hasMessageAccessStatus
			? ReceivedHistorySyncMessageAccessStatusContent(
				completeAccessGranted: notification.messageAccessStatus.hasCompleteAccessGranted
					? notification.messageAccessStatus.completeAccessGranted
					: nil
			)
			: nil

		return ReceivedHistorySyncNotificationContent(
			fileSHA256: notification.hasFileSha256 ? notification.fileSha256 : nil,
			fileLength: notification.hasFileLength ? notification.fileLength : nil,
			mediaKey: notification.hasMediaKey ? notification.mediaKey : nil,
			fileEncSHA256: notification.hasFileEncSha256 ? notification.fileEncSha256 : nil,
			directPath: notification.hasDirectPath ? notification.directPath : nil,
			syncType: notification.hasSyncType ? historySyncType(notification.syncType) : nil,
			chunkOrder: notification.hasChunkOrder ? notification.chunkOrder : nil,
			originalMessageID: notification.hasOriginalMessageID ? notification.originalMessageID : nil,
			progress: notification.hasProgress ? notification.progress : nil,
			oldestMessageInChunkTimestampSeconds: notification.hasOldestMsgInChunkTimestampSec
				? notification.oldestMsgInChunkTimestampSec
				: nil,
			initialHistoryBootstrapInlinePayload: notification.hasInitialHistBootstrapInlinePayload
				? notification.initialHistBootstrapInlinePayload
				: nil,
			peerDataRequestSessionID: notification.hasPeerDataRequestSessionID
				? notification.peerDataRequestSessionID
				: nil,
			encryptedHandle: notification.hasEncHandle ? notification.encHandle : nil,
			messageAccessStatus: accessStatus
		)
	}

	static func appStateSyncKeyShareContent(
		_ share: Proto_Message.AppStateSyncKeyShare
	) -> ReceivedAppStateSyncKeyShareContent {
		ReceivedAppStateSyncKeyShareContent(keys: share.keys.map { key in
			let keyID = key.hasKeyID && key.keyID.hasKeyID ? key.keyID.keyID : nil
			let keyData = key.hasKeyData ? key.keyData : nil
			return ReceivedAppStateSyncKeyContent(
				keyID: keyID,
				keyIDBase64: keyID?.base64EncodedString(),
				keyData: keyData?.hasKeyData == true ? keyData?.keyData : nil,
				fingerprint: keyData?.hasFingerprint == true
					? appStateSyncKeyFingerprintContent(keyData!.fingerprint)
					: nil,
				timestamp: keyData?.hasTimestamp == true ? keyData?.timestamp : nil
			)
		})
	}

	static func appStateSyncKeyRequestContent(
		_ request: Proto_Message.AppStateSyncKeyRequest
	) -> ReceivedAppStateSyncKeyRequestContent {
		ReceivedAppStateSyncKeyRequestContent(keyIDs: request.keyIds.map { keyID in
			let data = keyID.hasKeyID ? keyID.keyID : nil
			return ReceivedAppStateSyncKeyIDContent(
				keyID: data,
				keyIDBase64: data?.base64EncodedString()
			)
		})
	}

	private static func appStateSyncKeyFingerprintContent(
		_ fingerprint: Proto_Message.AppStateSyncKeyFingerprint
	) -> ReceivedAppStateSyncKeyFingerprintContent {
		ReceivedAppStateSyncKeyFingerprintContent(
			rawID: fingerprint.hasRawID ? fingerprint.rawID : nil,
			currentIndex: fingerprint.hasCurrentIndex ? fingerprint.currentIndex : nil,
			deviceIndexes: fingerprint.deviceIndexes
		)
	}

	static func lidMigrationMappingSyncContent(
		_ sync: Proto_LIDMigrationMappingSyncMessage
	) -> ReceivedLIDMigrationMappingSyncContent {
		guard sync.hasEncodedMappingPayload,
			  let payload = try? Proto_LIDMigrationMappingSyncPayload(serializedBytes: sync.encodedMappingPayload) else {
			return ReceivedLIDMigrationMappingSyncContent(chatDBMigrationTimestamp: nil, mappings: [])
		}

		return ReceivedLIDMigrationMappingSyncContent(
			chatDBMigrationTimestamp: payload.hasChatDbMigrationTimestamp ? payload.chatDbMigrationTimestamp : nil,
			mappings: payload.pnToLidMappings.map { mapping in
				let lid = mapping.hasLatestLid ? mapping.latestLid : mapping.assignedLid
				return ReceivedLIDMigrationMappingContent(
					phoneNumber: "\(mapping.pn)@s.whatsapp.net",
					lid: "\(lid)@lid",
					rawPhoneNumber: mapping.pn,
					assignedLID: mapping.assignedLid,
					latestLID: mapping.hasLatestLid ? mapping.latestLid : nil
				)
			}
		)
	}

	static func groupMemberLabelChangeContent(
		_ label: Proto_MemberLabel
	) -> ReceivedGroupMemberLabelChangeContent {
		ReceivedGroupMemberLabelChangeContent(
			label: label.hasLabel ? label.label : nil,
			labelTimestamp: label.hasLabelTimestamp ? label.labelTimestamp : nil
		)
	}

	static func peerDataOperationRequestResponseContent(
		_ response: Proto_Message.PeerDataOperationRequestResponseMessage
	) -> ReceivedPeerDataOperationRequestResponseContent {
		var messages: [ReceivedMessage] = []
		for result in response.peerDataOperationResult where result.hasPlaceholderMessageResendResponse {
			let placeholder = result.placeholderMessageResendResponse
			guard placeholder.hasWebMessageInfoBytes,
				  let info = try? Proto_WebMessageInfo(serializedBytes: placeholder.webMessageInfoBytes),
				  let received = ReceivedWebMessageInfoParser.parse(info) else {
				continue
			}

			messages.append(received)
		}

		return ReceivedPeerDataOperationRequestResponseContent(
			stanzaID: response.hasStanzaID ? response.stanzaID : nil,
			placeholderResendMessages: messages
		)
	}

	private static func historySyncType(_ type: Proto_Message.HistorySyncType) -> ReceivedHistorySyncType {
		switch type {
		case .initialBootstrap:
			.initialBootstrap
		case .initialStatusV3:
			.initialStatusV3
		case .full:
			.full
		case .recent:
			.recent
		case .pushName:
			.pushName
		case .nonBlockingData:
			.nonBlockingData
		case .onDemand:
			.onDemand
		case .noHistory:
			.noHistory
		case .messageAccessStatus:
			.messageAccessStatus
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	static func limitSharingContent(_ limitSharing: Proto_LimitSharing) -> ReceivedLimitSharingContent {
		ReceivedLimitSharingContent(
			sharingLimited: limitSharing.hasSharingLimited ? limitSharing.sharingLimited : nil,
			trigger: limitSharing.hasTrigger ? limitSharingTrigger(limitSharing.trigger) : nil,
			settingTimestampMilliseconds: limitSharing.hasLimitSharingSettingTimestamp ? limitSharing.limitSharingSettingTimestamp : nil,
			initiatedByMe: limitSharing.hasInitiatedByMe ? limitSharing.initiatedByMe : nil
		)
	}

	private static func limitSharingTrigger(_ trigger: Proto_LimitSharing.TriggerType) -> ReceivedLimitSharingTrigger {
		switch trigger {
		case .unknown:
			.unknown
		case .chatSetting:
			.chatSetting
		case .bizSupportsFbHosting:
			.bizSupportsFBHosting
		case .unknownGroup:
			.unknownGroup
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}
}
