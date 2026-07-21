import Foundation

public struct BaileysMessageRelayParticipant: Equatable, Sendable {
	public let jid: String
	public let count: Int

	public init(jid: String, count: Int) {
		self.jid = jid
		self.count = count
	}
}

public struct BaileysMessageRelayOptions: Equatable, Sendable {
	public let messageID: String?
	public let participant: BaileysMessageRelayParticipant?
	public let additionalAttributes: [String: String]
	public let additionalNodes: [BinaryNode]
	public let useUserDevicesCache: Bool
	public let statusJidList: [String]?

	public init(
		messageID: String? = nil,
		participant: BaileysMessageRelayParticipant? = nil,
		additionalAttributes: [String: String] = [:],
		additionalNodes: [BinaryNode] = [],
		useUserDevicesCache: Bool = true,
		statusJidList: [String]? = nil
	) {
		self.messageID = messageID
		self.participant = participant
		self.additionalAttributes = additionalAttributes
		self.additionalNodes = additionalNodes
		self.useUserDevicesCache = useUserDevicesCache
		self.statusJidList = statusJidList
	}
}

extension WhatsAppClient {
	@discardableResult
	public func relayMessage(
		to jid: String,
		encodedMessage: Data,
		options: BaileysMessageRelayOptions = BaileysMessageRelayOptions()
	) async throws -> String {
		try await relayMessage(
			to: jid,
			message: Proto_Message(serializedBytes: encodedMessage),
			options: options
		)
	}

	@discardableResult
	func relayMessage(
		to jid: String,
		message: Proto_Message,
		options: BaileysMessageRelayOptions = BaileysMessageRelayOptions()
	) async throws -> String {
		if let participant = options.participant {
			guard let messageEncryptor else {
				throw WhatsAppClientError.missingMessageEncryptor
			}

			let id = try options.messageID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
			let builder = MessageRelayBuilder(encoder: messageEncoder, encryptor: messageEncryptor)
			let stanza = try await builder.buildRetryMessageStanza(
				to: jid,
				messageID: id,
				message: message,
				participantJID: participant.jid,
				retryCount: participant.count,
				localUserJID: authenticationState?.credentials.me?.id,
				localUserLID: authenticationState?.credentials.me?.lid,
				additionalAttributes: options.additionalAttributes,
				additionalNodes: options.additionalNodes
			)
			try await sendNode(stanza)
			return id
		}

		if jid.isStatusBroadcastJID {
			return try await sendStatusRelayMessage(
				message: message,
				options: options
			)
		}

		return try await sendResolvedMessage(
			to: jid,
			message: message,
			messageID: options.messageID,
			additionalAttributes: options.additionalAttributes,
			additionalNodes: options.additionalNodes,
			useUserDevicesCache: options.useUserDevicesCache
		)
	}

	private func sendStatusRelayMessage(
		message: Proto_Message,
		options: BaileysMessageRelayOptions
	) async throws -> String {
		guard let messageEncryptor else {
			throw WhatsAppClientError.missingMessageEncryptor
		}
		guard let groupMessageEncryptor else {
			throw WhatsAppClientError.missingGroupMessageEncryptor
		}
		guard let signalSessionPreparer else {
			throw WhatsAppClientError.missingSignalSessionPreparer
		}
		guard let me = authenticationState?.credentials.me?.id else {
			throw WhatsAppClientError.missingAuthenticatedUser
		}

		let deviceJIDs = try await getUSyncDevices(
			options.statusJidList ?? [],
			useCache: options.useUserDevicesCache,
			ignoreZeroDevices: false
		).map(\.jid)
		_ = try await signalSessionPreparer.assertSessions(for: deviceJIDs, force: false)
		let messageID = try options.messageID ?? messageIDGenerator.generateV2(userID: me)
		let stanza = try await MessageRelayBuilder(
			encoder: messageEncoder,
			encryptor: messageEncryptor,
			groupEncryptor: groupMessageEncryptor
		).buildGroupMessageStanza(
			to: "status@broadcast",
			messageID: messageID,
			message: message,
			senderJID: authenticationState?.credentials.me?.lid ?? me,
			senderKeyRecipientDeviceJIDs: deviceJIDs,
			additionalAttributes: options.additionalAttributes,
			additionalNodes: options.additionalNodes
		)
		try await sendNode(stanza)
		cacheRecentSentMessage(destinationJID: "status@broadcast", id: messageID, message: message)
		return messageID
	}
}
