import Foundation

public struct EncryptedMedia: Equatable, Sendable {
	public let encryptedFile: Data
	public let mac: Data
	public let fileEncSha256: Data
	public let fileSha256: Data
	public let fileLength: Int
}

public enum MediaEncryption {
	public static func encrypt(_ plaintext: Data, mediaKey: Data, mediaType: MediaType) throws -> EncryptedMedia {
		let keys = try MediaKeyDerivation.deriveKeys(from: mediaKey, mediaType: mediaType)
		let ciphertext: Data
		do {
			ciphertext = try AESCBCipher.encrypt(plaintext, key: keys.cipherKey, iv: keys.iv)
		} catch AESCBCipherError.cryptFailed(let status) {
			throw MediaEncryptionError.aesCBCEncryptionFailed(status)
		}
		let mac = CryptoDigest.hmacSign(keys.iv + ciphertext, key: keys.macKey).prefixData(10)
		let encryptedFile = ciphertext + mac

		return EncryptedMedia(
			encryptedFile: encryptedFile,
			mac: mac,
			fileEncSha256: CryptoDigest.sha256(encryptedFile),
			fileSha256: CryptoDigest.sha256(plaintext),
			fileLength: plaintext.count
		)
	}
}

public enum MediaEncryptionError: Error, Equatable, Sendable {
	case aesCBCEncryptionFailed(Int32)
}

private extension Data {
	func prefixData(_ count: Int) -> Data {
		Data(prefix(count))
	}
}
