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
		guard let destinationJID = request.key.remoteJID else {
			throw WhatsAppClientError.missingMessageDestination
		}

		let messageIDs = retryMessageIDs(from: request)
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

			let recipientDeviceJIDs = try await messageDeviceResolver.deviceJIDs(for: request.requesterJID)
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
			guard let message = recentSentMessage(destinationJID: destinationJID, id: id) else {
				continue
			}

			let retryKey = RetryResendKey(destinationJID: destinationJID, messageID: id, requesterJID: requesterJID)
			guard canResendMessage(for: retryKey) else {
				continue
			}

			guard !requesterDeviceJIDs.isEmpty else {
				continue
			}

			for deviceJID in requesterDeviceJIDs {
				let stanza = try await builder.buildRetryMessageStanza(
					to: destinationJID,
					messageID: id,
					message: message,
					participantJID: deviceJID,
					retryCount: retryCount,
					localUserJID: authenticationState?.credentials.me?.id,
					localUserLID: authenticationState?.credentials.me?.lid
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
			guard let message = recentSentMessage(destinationJID: destinationJID, id: id) else {
				continue
			}

			let retryKey = RetryResendKey(
				destinationJID: destinationJID,
				messageID: id,
				requesterJID: request.requesterJID
			)
			guard canResendMessage(for: retryKey) else {
				continue
			}

			let stanza = try await builder.buildRetryMessageStanza(
				to: destinationJID,
				messageID: id,
				message: message,
				participantJID: request.requesterJID,
				retryCount: request.retryCount,
				localUserJID: authenticationState?.credentials.me?.id,
				localUserLID: authenticationState?.credentials.me?.lid
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

	func cacheRecentSentMessage(destinationJID: String, id: String, message: Proto_Message) {
		pruneExpiredRecentSentMessages()
		let key = RecentSentMessageKey(destinationJID: destinationJID, id: id)
		if recentSentMessages[key] == nil {
			recentSentMessageOrder.append(key)
		}

		recentSentMessages[key] = RecentSentMessage(message: message, timestamp: Date())
		while recentSentMessageOrder.count > recentSentMessageLimit {
			recentSentMessages.removeValue(forKey: recentSentMessageOrder.removeFirst())
		}
	}

	private func recentSentMessage(destinationJID: String, id: String) -> Proto_Message? {
		pruneExpiredRecentSentMessages()
		return recentSentMessages[RecentSentMessageKey(destinationJID: destinationJID, id: id)]?.message
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
}

struct RetryResendKey: Hashable, Sendable {
	let destinationJID: String
	let messageID: String
	let requesterJID: String
}
