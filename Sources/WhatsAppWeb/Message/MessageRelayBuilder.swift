import Foundation

public enum SignalDirectCiphertextType: String, Equatable, Sendable {
	case signalMessage = "msg"
	case preKeySignalMessage = "pkmsg"
}

public struct EncryptedMessage: Equatable, Sendable {
	public let type: String
	public let ciphertextType: SignalDirectCiphertextType?
	public let ciphertext: Data

	public init(type: String, ciphertext: Data) {
		self.type = type
		self.ciphertextType = SignalDirectCiphertextType(rawValue: type)
		self.ciphertext = ciphertext
	}

	public init(ciphertextType: SignalDirectCiphertextType, ciphertext: Data) {
		self.type = ciphertextType.rawValue
		self.ciphertextType = ciphertextType
		self.ciphertext = ciphertext
	}
}

public struct EncryptedGroupMessage: Equatable, Sendable {
	public let ciphertext: Data
	public let senderKeyDistributionMessage: Data

	public init(ciphertext: Data, senderKeyDistributionMessage: Data) {
		self.ciphertext = ciphertext
		self.senderKeyDistributionMessage = senderKeyDistributionMessage
	}
}

struct MessageParticipantNodes: Equatable, Sendable {
	let nodes: [BinaryNode]
	let shouldIncludeDeviceIdentity: Bool
}

public struct SignalDirectMessageEncryptionRequest: Equatable, Sendable {
	public let jid: String
	public let localJID: String?
	public let data: Data
	public let address: SignalProtocolAddress
	public let localAddress: SignalProtocolAddress?

	public init(jid: String, localJID: String? = nil, data: Data) throws {
		guard !data.isEmpty else {
			throw SignalMessageEncryptionRequestValidationError.emptyMessageData
		}

		self.jid = jid
		self.localJID = localJID
		self.data = data
		self.address = try SignalProtocolAddress.validated(jid: jid)
		if let localJID {
			self.localAddress = try SignalProtocolAddress.validated(jid: localJID)
		} else {
			self.localAddress = nil
		}
	}
}

public struct SignalGroupMessageEncryptionRequest: Equatable, Sendable {
	public let groupJID: String
	public let senderJID: String
	public let data: Data
	public let senderAddress: SignalProtocolAddress

	public init(groupJID: String, senderJID: String, data: Data) throws {
		guard groupJID.isGroupJID || groupJID.isStatusBroadcastJID else {
			throw SignalMessageEncryptionRequestValidationError.invalidGroupJID
		}
		guard !data.isEmpty else {
			throw SignalMessageEncryptionRequestValidationError.emptyMessageData
		}

		self.groupJID = groupJID
		self.senderJID = senderJID
		self.data = data
		self.senderAddress = try SignalProtocolAddress.validated(jid: senderJID)
	}
}

public enum SignalMessageEncryptionRequestValidationError: Error, Equatable, Sendable {
	case invalidGroupJID
	case emptyMessageData
}

public protocol SignalAddressedMessageEncrypting: Sendable {
	func encryptMessage(_ request: SignalDirectMessageEncryptionRequest) async throws -> EncryptedMessage
}

public protocol SignalAddressedGroupMessageEncrypting: Sendable {
	func encryptGroupMessage(_ request: SignalGroupMessageEncryptionRequest) async throws -> EncryptedGroupMessage
}

public protocol MessageEncrypting: Sendable {
	func encryptMessage(jid: String, data: Data) async throws -> EncryptedMessage
	func encryptMessage(_ request: SignalDirectMessageEncryptionRequest) async throws -> EncryptedMessage
}

public protocol GroupMessageEncrypting: Sendable {
	func encryptGroupMessage(group: String, senderJID: String, data: Data) async throws -> EncryptedGroupMessage
	func encryptGroupMessage(_ request: SignalGroupMessageEncryptionRequest) async throws -> EncryptedGroupMessage
}

public extension MessageEncrypting {
	func encryptMessage(_ request: SignalDirectMessageEncryptionRequest) async throws -> EncryptedMessage {
		try await encryptMessage(jid: request.jid, data: request.data)
	}
}

public extension GroupMessageEncrypting {
	func encryptGroupMessage(_ request: SignalGroupMessageEncryptionRequest) async throws -> EncryptedGroupMessage {
		try await encryptGroupMessage(group: request.groupJID, senderJID: request.senderJID, data: request.data)
	}
}

struct MessageRelayBuilder: Sendable {
	private let encoder: MessageEncoder
	private let encryptor: any MessageEncrypting
	private let groupEncryptor: (any GroupMessageEncrypting)?

	init(
		encoder: MessageEncoder = MessageEncoder(),
		encryptor: any MessageEncrypting,
		groupEncryptor: (any GroupMessageEncrypting)? = nil
	) {
		self.encoder = encoder
		self.encryptor = encryptor
		self.groupEncryptor = groupEncryptor
	}

	func buildDirectMessageStanza(
		to destinationJID: String,
		messageID: String,
		message: Proto_Message,
		recipientDeviceJIDs: [String],
		localJID: String? = nil,
		localLID: String? = nil,
		additionalAttributes: [String: String] = [:],
		additionalNodes: [BinaryNode] = []
	) async throws -> BinaryNode {
		guard !recipientDeviceJIDs.isEmpty else {
			throw MessageRelayBuilderError.missingRecipientDevices
		}

		let encodedMessage = try encoder.encode(message)
		let encodedDeviceSentMessage = additionalAttributes["category"] == "peer"
			? nil
			: try encoder.encode(deviceSentMessage(message, destinationJID: destinationJID))
		let participants = try await createParticipantNodes(
			recipientDeviceJIDs: recipientDeviceJIDs,
			encodedMessage: encodedMessage,
			encodedDeviceSentMessage: encodedDeviceSentMessage,
			localJID: localJID,
			localLID: localLID
		)

		var attrs = [
			("id", messageID),
			("to", destinationJID),
			("type", "text")
		]
		if additionalAttributes["phash"] == nil {
			attrs.append(("phash", ParticipantHashGenerator.generateV2(participants: recipientDeviceJIDs)))
		}

		for (key, value) in additionalAttributes {
			attrs.append((key, value))
		}

		var contentNodes = [
			BinaryNode(
				tag: "participants",
				content: .nodes(participants.nodes)
			)
		] + additionalNodes
		if MessageReportingTokenBuilder.shouldIncludeReportingToken(message),
		   let reportingNode = MessageReportingTokenBuilder.reportingNode(
		   	encodedMessage: encodedMessage,
		   	message: message,
		   	key: WhatsAppMessageKey(remoteJID: destinationJID, fromMe: true, id: messageID)
		   ) {
			contentNodes.append(reportingNode)
		}

		return BinaryNode(
			tag: "message",
			attrs: BinaryNodeAttributes(attrs),
			content: .nodes(contentNodes)
		)
	}

	func createParticipantNodes(
		recipientDeviceJIDs: [String],
		message: Proto_Message,
		deviceSentMessage: Proto_Message? = nil,
		localJID: String? = nil,
		localLID: String? = nil,
		extraAttributes: [String: String] = [:]
	) async throws -> MessageParticipantNodes {
		try await createParticipantNodes(
			recipientDeviceJIDs: recipientDeviceJIDs,
			encodedMessage: try encoder.encode(message),
			encodedDeviceSentMessage: try deviceSentMessage.map { try encoder.encode($0) },
			localJID: localJID,
			localLID: localLID,
			extraAttributes: extraAttributes
		)
	}

	func buildGroupMessageStanza(
		to groupJID: String,
		messageID: String,
		message: Proto_Message,
		senderJID: String,
		senderKeyRecipientDeviceJIDs: [String],
		additionalAttributes: [String: String] = [:],
		additionalNodes: [BinaryNode] = []
	) async throws -> BinaryNode {
		guard let groupEncryptor else {
			throw MessageRelayBuilderError.missingGroupEncryptor
		}

		let encodedMessage = try encoder.encode(message)
		let encrypted = try await groupEncryptor.encryptGroupMessage(SignalGroupMessageEncryptionRequest(
			groupJID: groupJID,
			senderJID: senderJID,
			data: encodedMessage
		))
		guard !encrypted.ciphertext.isEmpty else {
			throw MessageRelayBuilderError.emptyGroupCiphertext
		}
		var contentNodes: [BinaryNode] = []
		let participantNodes = try await senderKeyParticipantNodes(
			groupJID: groupJID,
			senderKeyDistributionMessage: encrypted.senderKeyDistributionMessage,
			recipientDeviceJIDs: senderKeyRecipientDeviceJIDs,
			localJID: senderJID
		)
		if !participantNodes.isEmpty {
			contentNodes.append(BinaryNode(tag: "participants", content: .nodes(participantNodes)))
		}

		contentNodes.append(contentsOf: additionalNodes)
		contentNodes.append(BinaryNode(
			tag: "enc",
			attrs: ["v": "2", "type": "skmsg"],
			content: .data(encrypted.ciphertext)
		))
		if MessageReportingTokenBuilder.shouldIncludeReportingToken(message),
		   let reportingNode = MessageReportingTokenBuilder.reportingNode(
		   	encodedMessage: encodedMessage,
		   	message: message,
		   	key: WhatsAppMessageKey(remoteJID: groupJID, fromMe: true, id: messageID)
		   ) {
			contentNodes.append(reportingNode)
		}

		var attrs = [
			("id", messageID),
			("to", groupJID),
			("type", "text")
		]
		for (key, value) in additionalAttributes {
			attrs.append((key, value))
		}

		return BinaryNode(tag: "message", attrs: BinaryNodeAttributes(attrs), content: .nodes(contentNodes))
	}

	func buildRetryMessageStanza(
		to destinationJID: String,
		messageID: String,
		message: Proto_Message,
		participantJID: String,
		retryCount: Int,
		localUserJID: String?,
		localUserLID: String?,
		additionalAttributes: [String: String] = [:],
		additionalNodes: [BinaryNode] = []
	) async throws -> BinaryNode {
		let encodedMessage = try encoder.encode(message)
		let encrypted = try await encryptor.encryptMessage(SignalDirectMessageEncryptionRequest(
			jid: participantJID,
			localJID: localUserJID,
			data: encodedMessage
		))
		guard !encrypted.ciphertext.isEmpty else {
			throw MessageRelayBuilderError.emptyDirectCiphertext
		}
		var attrs: [(String, String)] = [
			("id", messageID),
			("type", "text")
		]
		for (key, value) in additionalAttributes {
			attrs.append((key, value))
		}

		if destinationJID.isGroupJID {
			attrs.append(("to", destinationJID))
			attrs.append(("participant", participantJID))
		} else if JID.areSameUser(participantJID, localUserJID) || JID.areSameUser(participantJID, localUserLID) {
			attrs.append(("to", participantJID))
			attrs.append(("recipient", destinationJID))
		} else {
			attrs.append(("to", participantJID))
		}

		let contentNodes = [
			BinaryNode(
				tag: "enc",
				attrs: ["v": "2", "type": encrypted.type, "count": String(retryCount)],
				content: .data(encrypted.ciphertext)
			)
		] + additionalNodes

		return BinaryNode(
			tag: "message",
			attrs: BinaryNodeAttributes(attrs),
			content: .nodes(contentNodes)
		)
	}

	private func senderKeyParticipantNodes(
		groupJID: String,
		senderKeyDistributionMessage: Data,
		recipientDeviceJIDs: [String],
		localJID: String
	) async throws -> [BinaryNode] {
		guard !recipientDeviceJIDs.isEmpty else {
			return []
		}
		guard !senderKeyDistributionMessage.isEmpty else {
			throw MessageRelayBuilderError.emptySenderKeyDistributionMessage
		}

		var distribution = Proto_Message.SenderKeyDistributionMessage()
		distribution.groupID = groupJID
		distribution.axolotlSenderKeyDistributionMessage = senderKeyDistributionMessage
		var senderKeyMessage = Proto_Message()
		senderKeyMessage.senderKeyDistributionMessage = distribution

		let encodedSenderKeyMessage = try encoder.encode(senderKeyMessage)
		var participantNodes: [BinaryNode] = []
		for jid in recipientDeviceJIDs {
			let encrypted = try await encryptor.encryptMessage(SignalDirectMessageEncryptionRequest(
				jid: jid,
				localJID: localJID,
				data: encodedSenderKeyMessage
			))
			guard !encrypted.ciphertext.isEmpty else {
				throw MessageRelayBuilderError.emptyDirectCiphertext
			}
			participantNodes.append(BinaryNode(
				tag: "to",
				attrs: ["jid": jid],
				content: .nodes([
					BinaryNode(
						tag: "enc",
						attrs: ["v": "2", "type": encrypted.type],
						content: .data(encrypted.ciphertext)
					)
				])
			))
		}

		return participantNodes
	}

	private func createParticipantNodes(
		recipientDeviceJIDs: [String],
		encodedMessage: Data,
		encodedDeviceSentMessage: Data? = nil,
		localJID: String? = nil,
		localLID: String? = nil,
		extraAttributes: [String: String] = [:]
	) async throws -> MessageParticipantNodes {
		guard !recipientDeviceJIDs.isEmpty else {
			return MessageParticipantNodes(nodes: [], shouldIncludeDeviceIdentity: false)
		}

		var nodes: [BinaryNode] = []
		var shouldIncludeDeviceIdentity = false
		for jid in recipientDeviceJIDs {
			let messageData: Data
			if let encodedDeviceSentMessage,
			   shouldUseDeviceSentMessage(for: jid, localJID: localJID, localLID: localLID) {
				messageData = encodedDeviceSentMessage
			} else {
				messageData = encodedMessage
			}
			let encrypted = try await encryptor.encryptMessage(SignalDirectMessageEncryptionRequest(
				jid: jid,
				localJID: localJID,
				data: messageData
			))
			guard !encrypted.ciphertext.isEmpty else {
				throw MessageRelayBuilderError.emptyDirectCiphertext
			}
			if encrypted.ciphertextType == .preKeySignalMessage {
				shouldIncludeDeviceIdentity = true
			}

			var attrs = [("v", "2"), ("type", encrypted.type)]
			for (key, value) in extraAttributes {
				attrs.append((key, value))
			}
			nodes.append(BinaryNode(
				tag: "to",
				attrs: ["jid": jid],
				content: .nodes([
					BinaryNode(tag: "enc", attrs: BinaryNodeAttributes(attrs), content: .data(encrypted.ciphertext))
				])
			))
		}

		return MessageParticipantNodes(nodes: nodes, shouldIncludeDeviceIdentity: shouldIncludeDeviceIdentity)
	}

	private func shouldUseDeviceSentMessage(for recipientJID: String, localJID: String?, localLID: String?) -> Bool {
		(JID.areSameUser(recipientJID, localJID) || JID.areSameUser(recipientJID, localLID)) &&
			recipientJID != localJID &&
			recipientJID != localLID
	}

	private func deviceSentMessage(_ message: Proto_Message, destinationJID: String) -> Proto_Message {
		var deviceSent = Proto_Message.DeviceSentMessage()
		deviceSent.destinationJid = destinationJID
		deviceSent.message = message

		var envelope = Proto_Message()
		envelope.deviceSentMessage = deviceSent
		if message.hasMessageContextInfo {
			envelope.messageContextInfo = message.messageContextInfo
		}

		return envelope
	}
}

enum MessageRelayBuilderError: Error, Equatable, Sendable {
	case missingRecipientDevices
	case missingGroupEncryptor
	case emptyDirectCiphertext
	case emptyGroupCiphertext
	case emptySenderKeyDistributionMessage
}
