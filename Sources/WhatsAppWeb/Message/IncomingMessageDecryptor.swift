import Foundation

protocol IncomingMessageDecrypting: Sendable {
	func decryptIncomingMessage(from node: BinaryNode) async throws -> Proto_Message?
}

public protocol SignalMessageDecrypting: Sendable {
	func decryptMessage(jid: String, type: String, ciphertext: Data) async throws -> Data
	func decryptGroupMessage(group: String, authorJID: String, ciphertext: Data) async throws -> Data
	func processSenderKeyDistributionMessage(
		authorJID: String,
		messageData: Data
	) async throws
	func decryptMessage(_ request: SignalDirectMessageDecryptionRequest) async throws -> Data
	func decryptGroupMessage(_ request: SignalGroupMessageDecryptionRequest) async throws -> Data
	func processSenderKeyDistributionMessage(_ request: SenderKeyDistributionMessageRequest) async throws
}

public protocol SignalAddressedMessageDecrypting: Sendable {
	func decryptMessage(_ request: SignalDirectMessageDecryptionRequest) async throws -> Data
	func decryptGroupMessage(_ request: SignalGroupMessageDecryptionRequest) async throws -> Data
	func processSenderKeyDistributionMessage(_ request: SenderKeyDistributionMessageRequest) async throws
}

public struct SignalDirectMessageDecryptionRequest: Equatable, Sendable {
	public let jid: String
	public let type: String
	public let ciphertextType: SignalDirectCiphertextType
	public let localJID: String?
	public let ciphertext: Data
	public let address: SignalProtocolAddress
	public let localAddress: SignalProtocolAddress?

	public init(jid: String, type: String, localJID: String? = nil, ciphertext: Data) throws {
		guard let ciphertextType = SignalDirectCiphertextType(rawValue: type) else {
			throw SignalMessageDecryptionRequestValidationError.unsupportedDirectCiphertextType(type)
		}
		guard !ciphertext.isEmpty else {
			throw SignalMessageDecryptionRequestValidationError.emptyCiphertext
		}

		self.jid = jid
		self.type = type
		self.ciphertextType = ciphertextType
		self.localJID = localJID
		self.ciphertext = ciphertext
		self.address = try SignalProtocolAddress.validated(jid: jid)
		if let localJID {
			self.localAddress = try SignalProtocolAddress.validated(jid: localJID)
		} else {
			self.localAddress = nil
		}
	}

	public init(jid: String, ciphertextType: SignalDirectCiphertextType, localJID: String? = nil, ciphertext: Data) throws {
		try self.init(jid: jid, type: ciphertextType.rawValue, localJID: localJID, ciphertext: ciphertext)
	}
}

public struct SignalGroupMessageDecryptionRequest: Equatable, Sendable {
	public let groupJID: String
	public let authorJID: String
	public let ciphertext: Data
	public let authorAddress: SignalProtocolAddress

	public init(groupJID: String, authorJID: String, ciphertext: Data) throws {
		guard groupJID.isGroupJID else {
			throw SignalMessageDecryptionRequestValidationError.invalidGroupJID
		}
		guard !ciphertext.isEmpty else {
			throw SignalMessageDecryptionRequestValidationError.emptyCiphertext
		}

		self.groupJID = groupJID
		self.authorJID = authorJID
		self.ciphertext = ciphertext
		self.authorAddress = try SignalProtocolAddress.validated(jid: authorJID)
	}
}

public struct SenderKeyDistributionMessageRequest: Equatable, Sendable {
	public let authorJID: String
	public let groupJID: String?
	public let senderKeyDistributionData: Data?
	public let messageData: Data
	public let authorAddress: SignalProtocolAddress

	public init(
		authorJID: String,
		groupJID: String? = nil,
		senderKeyDistributionData: Data? = nil,
		messageData: Data
	) throws {
		if let groupJID, !groupJID.isGroupJID {
			throw SignalMessageDecryptionRequestValidationError.invalidGroupJID
		}
		guard !messageData.isEmpty else {
			throw SignalMessageDecryptionRequestValidationError.emptySenderKeyDistributionMessage
		}

		self.authorJID = authorJID
		self.groupJID = groupJID
		self.senderKeyDistributionData = senderKeyDistributionData
		self.messageData = messageData
		self.authorAddress = try SignalProtocolAddress.validated(jid: authorJID)
	}
}

public enum SignalMessageDecryptionRequestValidationError: Error, Equatable, Sendable {
	case invalidGroupJID
	case unsupportedDirectCiphertextType(String)
	case emptyCiphertext
	case emptySenderKeyDistributionMessage
}

public extension SignalMessageDecrypting {
	func decryptMessage(_ request: SignalDirectMessageDecryptionRequest) async throws -> Data {
		try await decryptMessage(jid: request.jid, type: request.type, ciphertext: request.ciphertext)
	}

	func decryptGroupMessage(_ request: SignalGroupMessageDecryptionRequest) async throws -> Data {
		try await decryptGroupMessage(
			group: request.groupJID,
			authorJID: request.authorJID,
			ciphertext: request.ciphertext
		)
	}

	func processSenderKeyDistributionMessage(_ request: SenderKeyDistributionMessageRequest) async throws {
		try await processSenderKeyDistributionMessage(authorJID: request.authorJID, messageData: request.messageData)
	}
}

struct SignalIncomingMessageDecryptor: IncomingMessageDecrypting {
	private let signalDecryptor: any SignalMessageDecrypting
	private let localJIDProvider: @Sendable () async -> String?
	private let decryptionJIDResolver: SignalDecryptionJIDResolver.LIDMappingResolver?

	init(signalDecryptor: any SignalMessageDecrypting, localJID: String? = nil) {
		self.signalDecryptor = signalDecryptor
		self.localJIDProvider = { localJID }
		self.decryptionJIDResolver = nil
	}

	init(
		signalDecryptor: any SignalMessageDecrypting,
		localJIDProvider: @escaping @Sendable () async -> String?,
		decryptionJIDResolver: SignalDecryptionJIDResolver.LIDMappingResolver? = nil
	) {
		self.signalDecryptor = signalDecryptor
		self.localJIDProvider = localJIDProvider
		self.decryptionJIDResolver = decryptionJIDResolver
	}

	func decryptIncomingMessage(from node: BinaryNode) async throws -> Proto_Message? {
		guard node.tag == "message" else {
			return nil
		}
		let authorJID = node.attrs["participant"] ?? node.attrs["from"]
		let groupJID = node.attrs["from"].flatMap { $0.isGroupJID ? $0 : nil }

		if let plaintext = firstContentData(in: node, tag: "plaintext") {
			let message = try unwrapDeviceSentMessage(Proto_Message(serializedBytes: plaintext))
			try await processSenderKeyDistributionIfPresent(in: message, authorJID: authorJID, groupJID: groupJID)
			return message
		}

		guard let encryptedNode = node.firstChild(named: "enc"),
			  let ciphertext = encryptedNode.dataContent,
			  let type = encryptedNode.attrs["type"] else {
			return nil
		}
		guard !ciphertext.isEmpty else {
			throw SignalIncomingMessageDecryptorError.emptyCiphertext
		}

		let decrypted: Data
		if type == "skmsg" {
			guard let group = node.attrs["from"], let authorJID = node.attrs["participant"] else {
				return nil
			}

			decrypted = try await signalDecryptor.decryptGroupMessage(SignalGroupMessageDecryptionRequest(
				groupJID: group,
				authorJID: authorJID,
				ciphertext: ciphertext
			))
		} else {
			guard let jid = node.attrs["participant"] ?? node.attrs["from"] else {
				return nil
			}
			let decryptionJID = try await SignalDecryptionJIDResolver.resolve(
				senderJID: jid,
				resolveLIDForPN: decryptionJIDResolver
			)

			decrypted = try await signalDecryptor.decryptMessage(SignalDirectMessageDecryptionRequest(
				jid: decryptionJID,
				type: type,
				localJID: await localJIDProvider(),
				ciphertext: ciphertext
			))
		}
		let message = try unwrapDeviceSentMessage(Proto_Message(serializedBytes: unpadRandomMax16(decrypted)))
		try await processSenderKeyDistributionIfPresent(in: message, authorJID: authorJID, groupJID: groupJID)
		return message
	}

	private func firstContentData(in node: BinaryNode, tag: String) -> Data? {
		node.firstChild(named: tag)?.dataContent
	}

	private func unpadRandomMax16(_ data: Data) throws -> Data {
		do {
			return try MessagePadding.unpadded(data)
		} catch MessagePaddingError.emptyPaddedMessage {
			throw SignalIncomingMessageDecryptorError.emptyPaddedMessage
		} catch MessagePaddingError.invalidPadding {
			throw SignalIncomingMessageDecryptorError.invalidPadding
		} catch {
			throw error
		}
	}

	private func unwrapDeviceSentMessage(_ message: Proto_Message) -> Proto_Message {
		if message.hasDeviceSentMessage, message.deviceSentMessage.hasMessage {
			return message.deviceSentMessage.message
		}

		return message
	}

	private func processSenderKeyDistributionIfPresent(
		in message: Proto_Message,
		authorJID: String?,
		groupJID: String?
	) async throws {
		guard let authorJID else {
			return
		}

		if message.hasSenderKeyDistributionMessage {
			let distribution = message.senderKeyDistributionMessage
			try await signalDecryptor.processSenderKeyDistributionMessage(SenderKeyDistributionMessageRequest(
				authorJID: authorJID,
				groupJID: distribution.groupID.isEmpty ? groupJID : distribution.groupID,
				senderKeyDistributionData: distribution.hasAxolotlSenderKeyDistributionMessage
					? distribution.axolotlSenderKeyDistributionMessage
					: nil,
				messageData: try distribution.serializedData()
			))
		}

		if message.hasFastRatchetKeySenderKeyDistributionMessage {
			let distribution = message.fastRatchetKeySenderKeyDistributionMessage
			try await signalDecryptor.processSenderKeyDistributionMessage(SenderKeyDistributionMessageRequest(
				authorJID: authorJID,
				groupJID: distribution.groupID.isEmpty ? groupJID : distribution.groupID,
				senderKeyDistributionData: distribution.hasAxolotlSenderKeyDistributionMessage
					? distribution.axolotlSenderKeyDistributionMessage
					: nil,
				messageData: try distribution.serializedData()
			))
		}
	}
}

enum SignalIncomingMessageDecryptorError: Error, Equatable, Sendable {
	case emptyCiphertext
	case emptyPaddedMessage
	case invalidPadding
}

private extension BinaryNode {
	var dataContent: Data? {
		guard case .data(let data) = content else {
			return nil
		}

		return data
	}
}
