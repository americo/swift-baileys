import Foundation

extension WhatsAppClient {
	@discardableResult
	public func resendCachedMessage(for request: MessageRetryRequest) async throws -> String {
		guard let resentID = try await resendCachedMessages(for: request).first else {
			throw WhatsAppClientError.missingRetryMessage
		}

		return resentID
	}

	@discardableResult
	public func resendCachedMessages(for request: MessageRetryRequest) async throws -> [String] {
		let messageIDs = retryMessageIDs(from: request)
		guard let destinationJID = request.key.remoteJID ?? peerDestinationJID(of: messageIDs, requesterJID: request.requesterJID) else {
			throw WhatsAppClientError.missingMessageDestination
		}

		guard !messageIDs.isEmpty else {
			throw WhatsAppClientError.missingReceiptMessageIDs
		}

		guard let messageEncryptor else {
			throw WhatsAppClientError.missingMessageEncryptor
		}

		if JID(request.requesterJID)?.device == nil {
			guard let signalSessionPreparer else {
				throw WhatsAppClientError.missingSignalSessionPreparer
			}

			guard let messageDeviceResolver else {
				throw WhatsAppClientError.missingMessageDeviceResolver
			}

			let me = authenticationState?.credentials.me
			let recipientDeviceJIDs = try await messageDeviceResolver.deviceJIDs(for: request.requesterJID).filter {
				!OwnDeviceAddressing.isSendingDevice($0, localJID: me?.id, localLID: me?.lid)
			}
			_ = try await signalSessionPreparer.assertSessions(for: recipientDeviceJIDs, force: true)
			return try await resendCachedMessages(
				destinationJID: destinationJID,
				messageIDs: messageIDs,
				requesterJID: request.requesterJID,
				requesterDeviceJIDs: recipientDeviceJIDs,
				retryCount: request.retryCount,
				encryptor: messageEncryptor
			)
		}

		if try await !injectRetrySessionBundleIfAvailable(request) {
			guard let signalSessionPreparer else {
				throw WhatsAppClientError.missingSignalSessionPreparer
			}

			_ = try await signalSessionPreparer.assertSessions(for: [request.requesterJID], force: true)
		}

		return try await resendCachedMessages(
			destinationJID: destinationJID,
			messageIDs: messageIDs,
			request: request,
			encryptor: messageEncryptor
		)
	}

	/// A retry from our own phone names no recipient, as what it could not read was sent to ourselves.
	/// The phone may answer by LID about a request sent by phone number, or the reverse.
	private func peerDestinationJID(of messageIDs: [String], requesterJID: String) -> String? {
		let me = authenticationState?.credentials.me
		guard OwnDeviceAddressing.isOwnUser(requesterJID, localJID: me?.id, localLID: me?.lid) else {
			return nil
		}

		let ownJIDs = [me?.id, me?.lid].compactMap { $0.flatMap { JID($0)?.normalizedUser } }
		return ownJIDs.first { jid in
			messageIDs.contains { recentSentMessageEntry(destinationJID: jid, id: $0)?.peerStanza != nil }
		}
	}

	private func injectRetrySessionBundleIfAvailable(_ request: MessageRetryRequest) async throws -> Bool {
		guard let retrySessionInjector,
			  let bundle = request.sessionBundle else {
			return false
		}

		guard let sessionBundle = try? bundle.signalSessionBundle(for: request.requesterJID) else {
			return false
		}

		if let nativeInstaller = retrySessionInjector as? any SignalNativeSessionInstalling {
			try await nativeInstaller.installSession(sessionBundle.nativeInstallRequest(
				localJID: authenticationState?.credentials.me?.id
			))
		} else {
			try await retrySessionInjector.injectSession(bundle: sessionBundle)
		}
		return true
	}

	private func retryMessageIDs(from request: MessageRetryRequest) -> [String] {
		var result: [String] = []
		for id in [request.key.id].compactMap({ $0 }) + request.messageIDs where !result.contains(id) {
			result.append(id)
		}

		return result
	}

	private func resendCachedMessages(
		destinationJID: String,
		messageIDs: [String],
		requesterJID: String,
		requesterDeviceJIDs: [String],
		retryCount: Int,
		encryptor: any MessageEncrypting
	) async throws -> [String] {
		var resentIDs: [String] = []
		let builder = MessageRelayBuilder(encoder: messageEncoder, encryptor: encryptor)
		for id in messageIDs {
			guard let source = retrySource(requestedDestinationJID: destinationJID, id: id) else {
				continue
			}

			let sent = source.message

			let retryKey = RetryResendKey(destinationJID: destinationJID, messageID: id, requesterJID: requesterJID)
			guard canResendMessage(for: retryKey) else {
				continue
			}

			// Peer requests are for the primary phone, the bare JID or device 0.
			let deviceJIDs = sent.peerStanza == nil
				? requesterDeviceJIDs
				: requesterDeviceJIDs.filter { (JID($0)?.device ?? 0) == 0 }
			guard !deviceJIDs.isEmpty else {
				continue
			}

			for deviceJID in deviceJIDs {
				let stanza = try await builder.buildRetryMessageStanza(
					to: source.destinationJID,
					messageID: id,
					message: sent.message,
					participantJID: deviceJID,
					retryCount: retryCount,
					localUserJID: authenticationState?.credentials.me?.id,
					localUserLID: authenticationState?.credentials.me?.lid,
					additionalAttributes: sent.peerStanza?.attributes ?? [:],
					additionalNodes: sent.peerStanza?.nodes ?? sent.metaNodes
				)
				try await sendNode(stanza)
			}
			recordRetryResend(for: retryKey)
			resentIDs.append(id)
		}

		return resentIDs
	}

	private func resendCachedMessages(
		destinationJID: String,
		messageIDs: [String],
		request: MessageRetryRequest,
		encryptor: any MessageEncrypting
	) async throws -> [String] {
		var resentIDs: [String] = []
		let builder = MessageRelayBuilder(encoder: messageEncoder, encryptor: encryptor)
		for id in messageIDs {
			guard let source = retrySource(requestedDestinationJID: destinationJID, id: id) else {
				continue
			}

			let sent = source.message

			let retryKey = RetryResendKey(
				destinationJID: destinationJID,
				messageID: id,
				requesterJID: request.requesterJID
			)
			guard canResendMessage(for: retryKey) else {
				continue
			}

			let stanza = try await builder.buildRetryMessageStanza(
				to: source.destinationJID,
				messageID: id,
				message: sent.message,
				participantJID: request.requesterJID,
				retryCount: request.retryCount,
				localUserJID: authenticationState?.credentials.me?.id,
				localUserLID: authenticationState?.credentials.me?.lid,
				additionalAttributes: sent.peerStanza?.attributes ?? [:],
				additionalNodes: sent.peerStanza?.nodes ?? sent.metaNodes
			)
			try await sendNode(stanza)
			recordRetryResend(for: retryKey)
			resentIDs.append(id)
		}

		return resentIDs
	}

	private func canResendMessage(for key: RetryResendKey) -> Bool {
		(retryResendCounts[key] ?? 0) < configuration.maxMessageRetryCount
	}

	private func recordRetryResend(for key: RetryResendKey) {
		retryResendCounts[key] = (retryResendCounts[key] ?? 0) + 1
	}

	func cacheRecentSentMessage(
		destinationJID: String,
		id: String,
		message: Proto_Message,
		additionalAttributes: [String: String] = [:],
		additionalNodes: [BinaryNode] = []
	) {
		pruneExpiredRecentSentMessages()
		let key = RecentSentMessageKey(destinationJID: destinationJID, id: id)
		if recentSentMessages[key] == nil {
			recentSentMessageOrder.append(key)
		}

		recentSentMessages[key] = RecentSentMessage(
			message: message,
			timestamp: Date(),
			peerStanza: additionalAttributes["category"] == "peer"
				? PeerStanzaParts(attributes: additionalAttributes, nodes: additionalNodes)
				: nil,
			metaNodes: additionalNodes.filter { $0.tag == "meta" }
		)
		while recentSentMessageOrder.count > recentSentMessageLimit {
			recentSentMessages.removeValue(forKey: recentSentMessageOrder.removeFirst())
		}
	}

	/// The sent message a retry asks for, and the address to name it by in the resend. A retry can name
	/// the conversation by LID when it was sent by phone number, or the reverse, so an exact miss falls
	/// back to the message id. The resend answers in the address the requester used: the server refuses
	/// a LID `to` with a phone-number `recipient` (error 400).
	func retrySource(requestedDestinationJID: String, id: String) -> (destinationJID: String, message: RecentSentMessage)? {
		if let exact = recentSentMessageEntry(destinationJID: requestedDestinationJID, id: id) {
			return (requestedDestinationJID, exact)
		}

		guard !requestedDestinationJID.isGroupJID,
			  let match = recentSentMessages.first(where: { $0.key.id == id && !$0.key.destinationJID.isGroupJID }) else {
			WhatsAppLog.logger.notice("message retry id=\(id, privacy: .public) asked for \(requestedDestinationJID, privacy: .public): not in the recent sends")
			return nil
		}

		WhatsAppLog.logger.notice("message retry id=\(id, privacy: .public) asked for \(requestedDestinationJID, privacy: .public), sent to \(match.key.destinationJID, privacy: .public)")
		return (JID(requestedDestinationJID)?.normalizedUser ?? requestedDestinationJID, match.value)
	}

	private func recentSentMessageEntry(destinationJID: String, id: String) -> RecentSentMessage? {
		pruneExpiredRecentSentMessages()
		return recentSentMessages[RecentSentMessageKey(destinationJID: destinationJID, id: id)]
	}

	private func pruneExpiredRecentSentMessages(now: Date = Date()) {
		let expired = recentSentMessages.filter {
			now.timeIntervalSince($0.value.timestamp) > recentSentMessageTTL
		}.map(\.key)
		guard !expired.isEmpty else {
			return
		}

		for key in expired {
			recentSentMessages.removeValue(forKey: key)
		}

		recentSentMessageOrder.removeAll { expired.contains($0) }
	}
}

private let recentSentMessageLimit = 512
private let recentSentMessageTTL: TimeInterval = 5 * 60

struct RecentSentMessageKey: Hashable, Sendable {
	let destinationJID: String
	let id: String
}

struct RecentSentMessage: Sendable {
	let message: Proto_Message
	let timestamp: Date
	/// What a peer message's stanza carried: without it a resend looks like a copy of a sent message.
	let peerStanza: PeerStanzaParts?
	/// The nodes that say what kind of message this is, such as a poll's `meta`.
	let metaNodes: [BinaryNode]
}

struct PeerStanzaParts: Sendable {
	let attributes: [String: String]
	let nodes: [BinaryNode]
}

struct RetryResendKey: Hashable, Sendable {
	let destinationJID: String
	let messageID: String
	let requesterJID: String
}
