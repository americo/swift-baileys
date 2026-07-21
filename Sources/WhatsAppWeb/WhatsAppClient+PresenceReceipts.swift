import Foundation

public enum WhatsAppPresence: String, Sendable {
	case unavailable
	case available
	case composing
	case recording
	case paused
}

public enum MessageReceiptType: String, Sendable {
	case read
	case readSelf = "read-self"
	case historySync = "hist_sync"
	case peerMessage = "peer_msg"
	case sender
	case inactive
	case played
}

public struct WhatsAppPresenceData: Equatable, Sendable {
	public let lastKnownPresence: WhatsAppPresence
	public let lastSeen: UInt64?
	public let groupOnlineCount: Int?

	public init(lastKnownPresence: WhatsAppPresence, lastSeen: UInt64? = nil, groupOnlineCount: Int? = nil) {
		self.lastKnownPresence = lastKnownPresence
		self.lastSeen = lastSeen
		self.groupOnlineCount = groupOnlineCount
	}
}

public struct WhatsAppPresenceUpdate: Equatable, Sendable {
	public let id: String
	public let presences: [String: WhatsAppPresenceData]

	public init(id: String, presences: [String: WhatsAppPresenceData]) {
		self.id = id
		self.presences = presences
	}
}

public struct WhatsAppMessageKey: Codable, Equatable, Sendable {
	public let remoteJID: String?
	public let remoteJIDAlt: String?
	public let fromMe: Bool
	public let id: String?
	public let participant: String?
	public let participantAlt: String?

	public init(
		remoteJID: String?,
		fromMe: Bool,
		id: String?,
		participant: String? = nil,
		remoteJIDAlt: String? = nil,
		participantAlt: String? = nil
	) {
		self.remoteJID = remoteJID
		self.remoteJIDAlt = remoteJIDAlt
		self.fromMe = fromMe
		self.id = id
		self.participant = participant
		self.participantAlt = participantAlt
	}
}

public struct MessageRetryRequest: Equatable, Sendable {
	public let key: WhatsAppMessageKey
	public let messageIDs: [String]
	public let requesterJID: String
	public let retryCount: Int
	public let timestamp: UInt64?
	public let requesterRegistrationID: Int?
	public let sessionBundle: MessageRetrySessionBundle?

	public init(
		key: WhatsAppMessageKey,
		messageIDs: [String],
		requesterJID: String,
		retryCount: Int,
		timestamp: UInt64? = nil,
		requesterRegistrationID: Int? = nil,
		sessionBundle: MessageRetrySessionBundle? = nil
	) {
		self.key = key
		self.messageIDs = messageIDs
		self.requesterJID = requesterJID
		self.retryCount = retryCount
		self.timestamp = timestamp
		self.requesterRegistrationID = requesterRegistrationID
		self.sessionBundle = sessionBundle
	}
}

public struct MessageRetrySessionBundle: Equatable, Sendable {
	public let registrationID: Int
	public let identityKey: Data
	public let signedPreKey: SignalPreKey
	public let preKey: SignalPreKey?

	public init(
		registrationID: Int,
		identityKey: Data,
		signedPreKey: SignalPreKey,
		preKey: SignalPreKey? = nil
	) {
		self.registrationID = registrationID
		self.identityKey = identityKey
		self.signedPreKey = signedPreKey
		self.preKey = preKey
	}

	public func signalSessionBundle(for requesterJID: String) throws -> SignalSessionBundle {
		guard let preKey else {
			throw MessageRetrySessionBundleValidationError.missingPreKey
		}

		let sessionBundle = SignalSessionBundle(
			jid: requesterJID,
			registrationID: registrationID,
			identityKey: identityKey,
			signedPreKey: signedPreKey,
			preKey: preKey
		)
		do {
			_ = try sessionBundle.validatedAddress()
		} catch let error as SignalSessionBundleValidationError {
			throw MessageRetrySessionBundleValidationError.invalidSessionBundle(error)
		}

		return sessionBundle
	}

	public func nativeInstallRequest(
		for requesterJID: String,
		localJID: String? = nil
	) throws -> SignalSessionNativeInstallRequest {
		try signalSessionBundle(for: requesterJID).nativeInstallRequest(localJID: localJID)
	}
}

public enum MessageRetrySessionBundleValidationError: Error, Equatable, Sendable {
	case missingPreKey
	case invalidSessionBundle(SignalSessionBundleValidationError)
}

extension WhatsAppClient {
	public func sendPresenceUpdate(_ presence: WhatsAppPresence, to jid: String? = nil) async throws {
		switch presence {
		case .available, .unavailable:
			guard let user = authenticationState?.credentials.me else {
				throw WhatsAppClientError.missingAuthenticatedUser
			}

			guard let name = user.name else {
				return
			}

			try await sendNode(BinaryNode(
				tag: "presence",
				attrs: [
					"name": name.replacingOccurrences(of: "@", with: ""),
					"type": presence.rawValue
				]
			))
		case .composing, .recording, .paused:
			guard let jid else {
				throw WhatsAppClientError.missingRecipientJID
			}

			guard let user = authenticationState?.credentials.me else {
				throw WhatsAppClientError.missingAuthenticatedUser
			}

			let from = JID(jid)?.server == JIDServer.lid.rawValue ? user.lid : user.id
			guard let from else {
				throw WhatsAppClientError.missingAuthenticatedUser
			}

			try await sendNode(BinaryNode(
				tag: "chatstate",
				attrs: ["from": from, "to": jid],
				content: .nodes([
					BinaryNode(
						tag: presence == .recording ? "composing" : presence.rawValue,
						attrs: presence == .recording ? ["media": "audio"] : [:]
					)
				])
			))
		}
	}

	public func presenceSubscribe(to jid: String, id: String? = nil) async throws {
		let stanzaID = try id ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let tokenNode = await TrustedContactTokenNodeBuilder.build(for: jid, keys: authenticationState?.keys)
		let content: BinaryNode.Content? = tokenNode.map { .nodes([$0]) }
		try await sendNode(BinaryNode(
			tag: "presence",
			attrs: ["to": jid, "id": stanzaID, "type": "subscribe"],
			content: content
		))
	}

	public func sendReceipt(
		to jid: String,
		participant: String? = nil,
		messageIDs: [String],
		type: MessageReceiptType,
		timestampSeconds: Int64? = nil
	) async throws {
		guard let firstMessageID = messageIDs.first else {
			throw WhatsAppClientError.missingReceiptMessageIDs
		}

		var attrs: [(String, String)] = [("id", firstMessageID)]
		if type == .sender, let participant, jid.isWhatsAppUserJID || jid.isLIDUserJID {
			attrs.append(("recipient", jid))
			attrs.append(("to", participant))
		} else {
			attrs.append(("to", jid))
			if let participant {
				attrs.append(("participant", participant))
			}
		}

		attrs.append(("type", type.rawValue))
		if type == .read || type == .readSelf {
			attrs.append(("t", String(timestampSeconds ?? UnixTimestamp.seconds())))
		}

		let remainingIDs = messageIDs.dropFirst()
		let content: BinaryNode.Content? = remainingIDs.isEmpty ? nil : .nodes([
			BinaryNode(
				tag: "list",
				content: .nodes(remainingIDs.map { BinaryNode(tag: "item", attrs: ["id": $0]) })
			)
		])
		try await sendNode(BinaryNode(tag: "receipt", attrs: BinaryNodeAttributes(attrs), content: content))
	}

	public func readMessages(
		_ keys: [WhatsAppMessageKey],
		type: MessageReceiptType? = nil,
		timestampSeconds: Int64? = nil
	) async throws {
		let type = if let type {
			type
		} else {
			if try await fetchPrivacySettings()["readreceipts"] == "all" {
				MessageReceiptType.read
			} else {
				MessageReceiptType.readSelf
			}
		}
		try await sendReceipts(keys, type: type, timestampSeconds: timestampSeconds)
	}

	public func sendReceipts(
		_ keys: [WhatsAppMessageKey],
		type: MessageReceiptType,
		timestampSeconds: Int64? = nil
	) async throws {
		for group in MessageKeyAggregator.aggregateMessageKeysNotFromMe(keys) {
			try await sendReceipt(
				to: group.jid,
				participant: group.participant,
				messageIDs: group.messageIDs,
				type: type,
				timestampSeconds: timestampSeconds
			)
		}
	}
}
