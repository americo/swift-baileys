import CryptoKit
import Foundation

public struct PollVoteCipher: Sendable {
	private let ivGenerator: @Sendable () throws -> Data

	public init(ivGenerator: @escaping @Sendable () throws -> Data = { try MessageIDGenerator.secureRandomBytes(count: 12) }) {
		self.ivGenerator = ivGenerator
	}

	func encrypt(
		selectedOptionHashes: [Data],
		pollMessageID: String,
		pollCreatorJID: String,
		voterJID: String,
		pollEncKey: Data
	) throws -> Proto_Message.PollEncValue {
		let iv = try ivGenerator()
		var vote = Proto_Message.PollVoteMessage()
		vote.selectedOptions = selectedOptionHashes
		let plaintext = try vote.serializedData()
		let key = Self.derivedKey(
			pollMessageID: pollMessageID,
			pollCreatorJID: pollCreatorJID,
			voterJID: voterJID,
			pollEncKey: pollEncKey
		)
		let box = try AES.GCM.seal(
			plaintext,
			using: SymmetricKey(data: key),
			nonce: AES.GCM.Nonce(data: iv),
			authenticating: Self.additionalAuthenticatedData(pollMessageID: pollMessageID, voterJID: voterJID)
		)
		var encrypted = Proto_Message.PollEncValue()
		encrypted.encPayload = box.ciphertext + box.tag
		encrypted.encIv = iv
		return encrypted
	}

	public func decrypt(
		_ content: ReceivedPollUpdateContent,
		pollMessageID: String,
		pollCreatorJID: String,
		voterJID: String,
		pollEncKey: Data
	) throws -> [Data] {
		guard let encryptedPayload = content.encryptedPayload else {
			throw PollVoteCipherError.missingEncryptedPayload
		}
		guard let encryptedIV = content.encryptedIV else {
			throw PollVoteCipherError.missingEncryptedIV
		}

		return try decrypt(
			encPayload: encryptedPayload,
			encIV: encryptedIV,
			pollMessageID: pollMessageID,
			pollCreatorJID: pollCreatorJID,
			voterJID: voterJID,
			pollEncKey: pollEncKey
		)
	}

	func decrypt(
		_ content: Proto_Message.PollEncValue,
		pollMessageID: String,
		pollCreatorJID: String,
		voterJID: String,
		pollEncKey: Data
	) throws -> [Data] {
		guard content.hasEncPayload else {
			throw PollVoteCipherError.missingEncryptedPayload
		}
		guard content.hasEncIv else {
			throw PollVoteCipherError.missingEncryptedIV
		}

		return try decrypt(
			encPayload: content.encPayload,
			encIV: content.encIv,
			pollMessageID: pollMessageID,
			pollCreatorJID: pollCreatorJID,
			voterJID: voterJID,
			pollEncKey: pollEncKey
		)
	}

	private func decrypt(
		encPayload encryptedPayload: Data,
		encIV encryptedIV: Data,
		pollMessageID: String,
		pollCreatorJID: String,
		voterJID: String,
		pollEncKey: Data
	) throws -> [Data] {
		guard encryptedPayload.count >= 16 else {
			throw PollVoteCipherError.invalidEncryptedPayloadLength
		}

		let tagStart = encryptedPayload.index(encryptedPayload.endIndex, offsetBy: -16)
		let box = try AES.GCM.SealedBox(
			nonce: AES.GCM.Nonce(data: encryptedIV),
			ciphertext: Data(encryptedPayload[..<tagStart]),
			tag: Data(encryptedPayload[tagStart...])
		)
		let key = Self.derivedKey(
			pollMessageID: pollMessageID,
			pollCreatorJID: pollCreatorJID,
			voterJID: voterJID,
			pollEncKey: pollEncKey
		)
		let plaintext = try AES.GCM.open(
			box,
			using: SymmetricKey(data: key),
			authenticating: Self.additionalAuthenticatedData(pollMessageID: pollMessageID, voterJID: voterJID)
		)
		return try Proto_Message.PollVoteMessage(serializedBytes: plaintext).selectedOptions
	}

	private static func derivedKey(
		pollMessageID: String,
		pollCreatorJID: String,
		voterJID: String,
		pollEncKey: Data
	) -> Data {
		let key0 = Data(HMAC<SHA256>.authenticationCode(
			for: pollEncKey,
			using: SymmetricKey(data: Data(repeating: 0, count: 32))
		))
		let sign = Data(pollMessageID.utf8)
			+ Data(pollCreatorJID.utf8)
			+ Data(voterJID.utf8)
			+ Data("Poll Vote".utf8)
			+ Data([1])
		return Data(HMAC<SHA256>.authenticationCode(for: sign, using: SymmetricKey(data: key0)))
	}

	private static func additionalAuthenticatedData(pollMessageID: String, voterJID: String) -> Data {
		Data("\(pollMessageID)\u{0000}\(voterJID)".utf8)
	}
}

public enum PollVoteCipherError: Error, Equatable {
	case missingEncryptedPayload
	case missingEncryptedIV
	case invalidEncryptedPayloadLength
}
