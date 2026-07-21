import CryptoKit
import Foundation

public struct DecryptedMediaRetryNotification: Equatable, Sendable {
	public let stanzaID: String?
	public let directPath: String?
	public let resultCode: Int?
	public let resultStatusCode: Int?
	public let messageSecret: Data?

	public init(stanzaID: String?, directPath: String?, resultCode: Int?, resultStatusCode: Int?, messageSecret: Data?) {
		self.stanzaID = stanzaID
		self.directPath = directPath
		self.resultCode = resultCode
		self.resultStatusCode = resultStatusCode
		self.messageSecret = messageSecret
	}
}

public enum MediaRetryCipher {
	public static func encryptRetryRequest(
		key: WhatsAppMessageKey,
		mediaKey: Data,
		meID: String,
		randomBytes: @Sendable (Int) throws -> Data = MessageIDGenerator.secureRandomBytes(count:)
	) throws -> BinaryNode {
		guard let messageID = key.id, let remoteJID = key.remoteJID else {
			throw MediaRetryCipherError.incompleteMessageKey
		}

		let iv = try randomBytes(12)
		guard iv.count == 12 else {
			throw MediaRetryCipherError.invalidIVLength
		}

		var receipt = Proto_ServerErrorReceipt()
		receipt.stanzaID = messageID
		let ciphertext = try AESGCMCipher.encrypt(
			try receipt.serializedData(),
			key: retryKey(from: mediaKey),
			iv: iv,
			additionalAuthenticatedData: Data(messageID.utf8)
		)

		return BinaryNode(tag: "receipt", attrs: [
			"id": messageID,
			"to": JID(meID)?.normalizedUser ?? meID,
			"type": "server-error"
		], content: .nodes([
			BinaryNode(tag: "encrypt", content: .nodes([
				BinaryNode(tag: "enc_p", content: .data(ciphertext)),
				BinaryNode(tag: "enc_iv", content: .data(iv))
			])),
			BinaryNode(tag: "rmr", attrs: .trimmingUndefined([
				("jid", remoteJID),
				("from_me", key.fromMe ? "true" : "false"),
				("participant", key.participant)
			]))
		]))
	}

	public static func decryptRetryNotification(
		_ media: RetriedMedia,
		mediaKey: Data,
		messageID: String
	) throws -> DecryptedMediaRetryNotification {
		let plaintext: Data
		do {
			plaintext = try AESGCMCipher.decrypt(
				media.ciphertext,
				key: retryKey(from: mediaKey),
				iv: media.iv,
				additionalAuthenticatedData: Data(messageID.utf8)
			)
		} catch AESGCMCipherError.invalidCiphertext {
			throw MediaRetryCipherError.invalidCiphertext
		}
		let notification = try Proto_MediaRetryNotification(serializedBytes: plaintext)
		let resultCode = notification.hasResult ? notification.result.rawValue : nil

		return DecryptedMediaRetryNotification(
			stanzaID: notification.hasStanzaID ? notification.stanzaID : nil,
			directPath: notification.hasDirectPath ? notification.directPath : nil,
			resultCode: resultCode,
			resultStatusCode: resultCode.flatMap(MediaRetryStatusCodeMapper.statusCode(for:)),
			messageSecret: notification.hasMessageSecret ? notification.messageSecret : nil
		)
	}
}

public enum MediaRetryCipherError: Error, Equatable, Sendable {
	case incompleteMessageKey
	case invalidIVLength
	case invalidCiphertext
}

private extension MediaRetryCipher {
	static func retryKey(from mediaKey: Data) -> Data {
		let key = HKDF<SHA256>.deriveKey(
			inputKeyMaterial: SymmetricKey(data: mediaKey),
			salt: Data(),
			info: Data("WhatsApp Media Retry Notification".utf8),
			outputByteCount: 32
		)
		return key.withUnsafeBytes { Data($0) }
	}
}
