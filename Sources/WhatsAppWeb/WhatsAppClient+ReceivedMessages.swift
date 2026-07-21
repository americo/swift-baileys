import Foundation

extension WhatsAppClient {
	func handleReceivedMessageNode(_ node: BinaryNode) async -> Bool {
		guard node.tag == "message" else {
			return false
		}
		if let from = node.attrs["from"],
		   from != "@s.whatsapp.net",
		   configuration.shouldIgnoreJID(from) == true {
			if let ack = StanzaAck.build(for: node, errorCode: 500, meID: authenticationState?.credentials.me?.id) {
				try? await sendNode(ack)
			}
			return true
		}

		guard let messageDecryptor else {
			return false
		}

		do {
			guard let protoMessage = try await messageDecryptor.decryptIncomingMessage(from: node),
				  let parsedContent = ReceivedMessageContentParser.parse(protoMessage),
				  let messageID = node.attrs["id"] else {
				return false
			}
			let parsedMessage = ReceivedMessage(
				id: messageID,
				from: node.attrs["from"],
				timestamp: node.attrs["t"].flatMap(UInt64.init),
				content: parsedContent,
				participant: node.attrs["participant"]
			)
			let receivedMessage = cleanedReceivedMessage(parsedMessage)
			let content = receivedMessage.content
			let from = receivedMessage.from
			let participant = receivedMessage.participant
			let timestamp = receivedMessage.timestamp

			if case .appStateSyncKeyShare(let share) = content {
				try? await storeAppStateSyncKeys(share)
			}
			if case .historySyncNotification(let notification) = content,
			   let history = try? await processHistorySyncNotification(
				notification,
				isLatest: historySyncIsLatest(for: notification)
			   ) {
				emitHistorySyncStatusIfNeeded(for: notification)
				try? await storeLIDMappings(history.lidPnMappings)
				try? await markHistorySyncNotificationProcessed(
					notification,
					messageID: messageID,
					from: from,
					participant: participant,
					timestamp: timestamp
				)
				eventContinuation.yield(.messagingHistorySet(history))
			}
			if case .peerDataOperationRequestResponse(let response) = content {
				for message in response.placeholderResendMessages {
					eventContinuation.yield(.receivedMessage(message))
				}
			}
			if case .lidMigrationMappingSync(let sync) = content {
				try? await storeLIDMappings(sync.mappings.map {
					LIDMapping(pn: $0.phoneNumber, lid: $0.lid)
				})
			}
			emitProtocolMessageUpdateIfNeeded(
				for: content,
				messageID: messageID,
				from: from,
				participant: participant,
				timestamp: timestamp
			)
			emitReactionUpdateIfNeeded(
				for: content,
				messageID: messageID,
				from: from,
				participant: participant
			)
			await emitPollUpdateIfNeeded(
				for: content,
				messageID: messageID,
				from: from,
				participant: participant
			)
			await emitEventResponseUpdateIfNeeded(
				for: content,
				messageID: messageID,
				from: from,
				participant: participant
			)
			emitGroupMemberLabelUpdateIfNeeded(
				for: content,
				from: from,
				participant: participant,
				participantAlt: node.attrs["participant_alt"] ?? node.attrs["participantAlt"],
				timestamp: timestamp
			)
			emitMessageActionUpdateIfNeeded(
				for: content,
				messageID: messageID,
				from: from,
				participant: participant,
				timestamp: timestamp
			)

			eventContinuation.yield(.receivedMessage(receivedMessage))
			if let ack = StanzaAck.build(for: node, meID: authenticationState?.credentials.me?.id) {
				try? await sendNode(ack)
			}
			if case .placeholder = content, let remoteJID = from {
				_ = try? await requestPlaceholderResend(for: WhatsAppMessageKey(
					remoteJID: remoteJID,
					fromMe: false,
					id: messageID,
					participant: participant
				))
			}

			return true
		} catch {
			eventContinuation.yield(.messageDecryptionFailed(MessageDecryptionFailure(
				id: node.attrs["id"],
				from: node.attrs["from"],
				participant: node.attrs["participant"],
				timestamp: node.attrs["t"].flatMap(UInt64.init),
				ciphertextType: node.firstChild(named: "enc")?.attrs["type"],
				reason: messageDecryptionFailureReason(from: error)
			)))
			return false
		}
	}

	private func cleanedReceivedMessage(_ message: ReceivedMessage) -> ReceivedMessage {
		guard let me = authenticationState?.credentials.me else {
			return MessageCleaner.cleaned(message, meID: "", meLID: "")
		}

		return MessageCleaner.cleaned(message, meID: me.id, meLID: me.lid ?? "")
	}

	private func emitEventResponseUpdateIfNeeded(
		for content: ReceivedMessageContent,
		messageID: String,
		from: String?,
		participant: String?
	) async {
		guard case .encryptedEventResponse(let response) = content else {
			return
		}

		let responseMessageKey = WhatsAppMessageKey(
			remoteJID: from,
			fromMe: false,
			id: messageID,
			participant: participant
		)
		let key = updateKey(from: response.eventCreationMessageKey, fallback: responseMessageKey)
		let decryptedResponse = await decryptedEventResponse(
			response,
			key: key,
			responseMessageKey: responseMessageKey
		)
		eventContinuation.yield(.messageEventResponsesUpdated([
			ReceivedMessageEventResponseUpdate(
				key: key,
				eventResponseMessageKey: responseMessageKey,
				encryptedPayload: response.encryptedPayload,
				encryptedIV: response.encryptedIV,
				response: decryptedResponse
			)
		]))
	}

	private func decryptedEventResponse(
		_ response: ReceivedEncryptedEventResponseContent,
		key: WhatsAppMessageKey,
		responseMessageKey: WhatsAppMessageKey
	) async -> ReceivedEventResponseContent? {
		guard let resolver = eventResponseContextResolver,
			  let context = try? await resolver.context(for: key, responseMessageKey: responseMessageKey) else {
			return nil
		}

		return try? EventResponseCipher().decrypt(
			response,
			eventMessageID: context.eventMessageID,
			eventCreatorJID: context.eventCreatorJID,
			responderJID: context.responderJID,
			eventMessageSecret: context.eventMessageSecret
		)
	}

	private func emitPollUpdateIfNeeded(
		for content: ReceivedMessageContent,
		messageID: String,
		from: String?,
		participant: String?
	) async {
		guard case .pollUpdate(let update) = content else {
			return
		}

		let pollUpdateMessageKey = WhatsAppMessageKey(
			remoteJID: from,
			fromMe: false,
			id: messageID,
			participant: participant
		)
		let key = updateKey(from: update.pollCreationMessageKey, fallback: pollUpdateMessageKey)
		let selectedOptionHashes = await decryptedPollVote(
			update,
			key: key,
			pollUpdateMessageKey: pollUpdateMessageKey
		)
		eventContinuation.yield(.messagePollUpdates([
			ReceivedMessagePollUpdate(
				key: key,
				pollUpdateMessageKey: pollUpdateMessageKey,
				encryptedPayload: update.encryptedPayload,
				encryptedIV: update.encryptedIV,
				senderTimestampMilliseconds: update.senderTimestampMilliseconds,
				selectedOptionHashes: selectedOptionHashes
			)
		]))
	}

	private func decryptedPollVote(
		_ update: ReceivedPollUpdateContent,
		key: WhatsAppMessageKey,
		pollUpdateMessageKey: WhatsAppMessageKey
	) async -> [Data]? {
		guard let resolver = pollVoteContextResolver,
			  let context = try? await resolver.context(for: key, pollUpdateMessageKey: pollUpdateMessageKey) else {
			return nil
		}

		return try? PollVoteCipher().decrypt(
			update,
			pollMessageID: context.pollMessageID,
			pollCreatorJID: context.pollCreatorJID,
			voterJID: context.voterJID,
			pollEncKey: context.pollEncKey
		)
	}

	private func emitMessageActionUpdateIfNeeded(
		for content: ReceivedMessageContent,
		messageID: String,
		from: String?,
		participant: String?,
		timestamp: UInt64?
	) {
		let envelopeKey = WhatsAppMessageKey(remoteJID: from, fromMe: false, id: messageID, participant: participant)
		switch content {
		case .messagePin(let pin):
			eventContinuation.yield(.messagesUpdated([
				ReceivedMessageUpdate(
					key: updateKey(from: pin.key, fallback: envelopeKey),
					status: nil,
					timestamp: pin.senderTimestampMilliseconds.map { UInt64($0 / 1_000) } ?? timestamp,
					content: content
				)
			]))
		case .messageKeep(let keep):
			eventContinuation.yield(.messagesUpdated([
				ReceivedMessageUpdate(
					key: updateKey(from: keep.key, fallback: envelopeKey),
					status: nil,
					timestamp: keep.timestampMilliseconds.map { UInt64($0 / 1_000) } ?? timestamp,
					content: content
				)
			]))
		default:
			break
		}
	}

	private func emitGroupMemberLabelUpdateIfNeeded(
		for content: ReceivedMessageContent,
		from: String?,
		participant: String?,
		participantAlt: String?,
		timestamp: UInt64?
	) {
		guard case .groupMemberLabelChange(let change) = content,
			  let groupID = from,
			  let label = change.label else {
			return
		}

		eventContinuation.yield(.groupMemberLabelUpdated(GroupMemberLabelUpdate(
			groupID: groupID,
			label: label,
			participant: participant,
			participantAlt: participantAlt,
			messageTimestamp: timestamp
		)))
	}

	private func emitReactionUpdateIfNeeded(
		for content: ReceivedMessageContent,
		messageID: String,
		from: String?,
		participant: String?
	) {
		guard case .reaction(let reaction) = content else {
			return
		}

		let reactionMessageKey = WhatsAppMessageKey(
			remoteJID: from,
			fromMe: false,
			id: messageID,
			participant: participant
		)
		eventContinuation.yield(.messageReactionsUpdated([
			ReceivedMessageReactionUpdate(
				key: updateKey(from: reaction.key, fallback: reactionMessageKey),
				reactionMessageKey: reactionMessageKey,
				text: reaction.text,
				groupingKey: reaction.groupingKey,
				senderTimestampMilliseconds: reaction.senderTimestampMilliseconds
			)
		]))
	}

	private func emitProtocolMessageUpdateIfNeeded(
		for content: ReceivedMessageContent,
		messageID: String,
		from: String?,
		participant: String?,
		timestamp: UInt64?
	) {
		let envelopeKey = WhatsAppMessageKey(remoteJID: from, fromMe: false, id: messageID, participant: participant)
		switch content {
		case .messageRevoked(let revoked):
			eventContinuation.yield(.messagesUpdated([
				ReceivedMessageUpdate(
					key: updateKey(from: revoked.key, fallback: envelopeKey),
					status: nil,
					timestamp: revoked.timestampMilliseconds.map { UInt64($0 / 1_000) } ?? timestamp,
					stub: ReceivedMessageStubContent(type: .revoke, parameters: []),
					protocolMessageKey: envelopeKey,
					protocolAction: .revoke
				)
			]))
		case .messageEdited(let edited):
			eventContinuation.yield(.messagesUpdated([
				ReceivedMessageUpdate(
					key: updateKey(from: edited.key, fallback: envelopeKey),
					status: nil,
					timestamp: edited.timestampMilliseconds.map { UInt64($0 / 1_000) } ?? timestamp,
					content: edited.content,
					protocolMessageKey: envelopeKey,
					protocolAction: .edit
				)
			]))
		case .ephemeralSetting(let setting):
			eventContinuation.yield(.messagesUpdated([
				ReceivedMessageUpdate(
					key: envelopeKey,
					status: nil,
					timestamp: setting.settingTimestampSeconds.map(UInt64.init) ?? timestamp,
					content: content,
					protocolMessageKey: envelopeKey,
					protocolAction: .ephemeralSetting
				)
			]))
		default:
			break
		}
	}

	private func updateKey(from key: ReceivedMessageKey?, fallback: WhatsAppMessageKey) -> WhatsAppMessageKey {
		WhatsAppMessageKey(
			remoteJID: key?.remoteJID ?? fallback.remoteJID,
			fromMe: key?.fromMe ?? fallback.fromMe,
			id: key?.id ?? fallback.id,
			participant: key?.participant ?? fallback.participant
		)
	}

	private func emitHistorySyncStatusIfNeeded(for notification: ReceivedHistorySyncNotificationContent) {
		switch notification.syncType {
		case .initialBootstrap where !initialBootstrapHistoryComplete:
			initialBootstrapHistoryComplete = true
			eventContinuation.yield(.messagingHistoryStatus(MessagingHistoryStatusUpdate(
				syncType: .initialBootstrap,
				status: .complete,
				explicit: true
			)))
		case .recent where notification.progress == 100 && !recentHistoryComplete:
			recentHistoryComplete = true
			recentHistoryPausedTask?.cancel()
			recentHistoryPausedTask = nil
			eventContinuation.yield(.messagingHistoryStatus(MessagingHistoryStatusUpdate(
				syncType: .recent,
				status: .complete,
				explicit: true
			)))
		case .recent where !recentHistoryComplete:
			scheduleRecentHistoryPausedStatus()
		default:
			break
		}
	}

	private func scheduleRecentHistoryPausedStatus() {
		recentHistoryPausedTask?.cancel()
		let timeout = configuration.historySyncPausedTimeout
		recentHistoryPausedTask = Task { [weak self] in
			do {
				try await Task.sleep(for: timeout)
			} catch {
				return
			}

			await self?.emitRecentHistoryPausedStatusIfNeeded()
		}
	}

	private func emitRecentHistoryPausedStatusIfNeeded() {
		guard !recentHistoryComplete else {
			return
		}

		recentHistoryComplete = true
		recentHistoryPausedTask = nil
		eventContinuation.yield(.messagingHistoryStatus(MessagingHistoryStatusUpdate(
			syncType: .recent,
			status: .paused,
			explicit: false
		)))
	}

	private func historySyncIsLatest(for notification: ReceivedHistorySyncNotificationContent) -> Bool? {
		guard notification.syncType != .onDemand else {
			return nil
		}

		return authenticationState?.credentials.processedHistoryMessages.isEmpty ?? true
	}

	private func markHistorySyncNotificationProcessed(
		_ notification: ReceivedHistorySyncNotificationContent,
		messageID: String,
		from: String?,
		participant: String?,
		timestamp: UInt64?
	) async throws {
		guard notification.syncType != .onDemand else {
			return
		}

		let processed = ProcessedHistoryMessage(
			key: WhatsAppMessageKey(
				remoteJID: from,
				fromMe: false,
				id: messageID,
				participant: participant
			),
			messageTimestamp: timestamp
		)

		try await updateCredentials { credentials in
			credentials.processedHistoryMessages.append(processed)
		}
	}

	private func messageDecryptionFailureReason(from error: any Error) -> MessageDecryptionFailureReason {
		if error is SignalProtocolAddressValidationError {
			return .invalidSignalAddress
		}

		switch error as? SignalMessageDecryptionRequestValidationError {
		case .invalidGroupJID:
			return .invalidGroupJID
		case .unsupportedDirectCiphertextType(let type):
			return .unsupportedDirectCiphertextType(type)
		default:
			break
		}

		switch error as? SignalIncomingMessageDecryptorError {
		case .emptyCiphertext:
			return .emptyCiphertext
		case .emptyPaddedMessage:
			return .emptyPaddedMessage
		case .invalidPadding:
			return .invalidPadding
		default:
			return .decryptionError(String(describing: error))
		}
	}
}

extension WhatsAppClient {
	public func processHistorySyncNotification(
		_ notification: ReceivedHistorySyncNotificationContent,
		isLatest: Bool? = nil
	) async throws -> MessagingHistorySet {
		let compressedPayload: Data
		if let inlinePayload = notification.initialHistoryBootstrapInlinePayload {
			compressedPayload = inlinePayload
		} else {
			guard let request = try ReceivedMessageContent.historySyncNotification(notification).mediaDownloadRequest() else {
				throw HistorySyncPayloadDecoderError.decompressionFailed
			}
			compressedPayload = try await mediaDownloader.download(request)
		}

		return try HistorySyncProcessor.process(
			HistorySyncPayloadDecoder.decodeCompressed(compressedPayload)
		).withNotificationMetadata(from: notification, isLatest: isLatest)
	}
}
