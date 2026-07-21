import Foundation

public enum MediaDecryption {
	public static func decrypt(
		_ encryptedFile: Data,
		mediaKey: Data,
		mediaType: MediaType,
		expectedFileEncSHA256: Data,
		expectedFileSHA256: Data
	) throws -> Data {
		guard CryptoDigest.sha256(encryptedFile) == expectedFileEncSHA256 else {
			throw MediaDecryptionError.fileEncSHA256Mismatch
		}

		guard encryptedFile.count > 10 else {
			throw MediaDecryptionError.missingAuthenticationCode
		}

		let keys = try MediaKeyDerivation.deriveKeys(from: mediaKey, mediaType: mediaType)
		let ciphertext = encryptedFile.dropLast(10)
		let receivedMAC = encryptedFile.suffix(10)
		let expectedMAC = CryptoDigest.hmacSign(keys.iv + ciphertext, key: keys.macKey).prefixData(10)
		guard receivedMAC == expectedMAC else {
			throw MediaDecryptionError.authenticationCodeMismatch
		}

		let plaintext: Data
		do {
			plaintext = try AESCBCipher.decrypt(Data(ciphertext), key: keys.cipherKey, iv: keys.iv)
		} catch AESCBCipherError.cryptFailed(let status) {
			throw MediaDecryptionError.aesCBCDecryptionFailed(status)
		}
		guard CryptoDigest.sha256(plaintext) == expectedFileSHA256 else {
			throw MediaDecryptionError.fileSHA256Mismatch
		}

		return plaintext
	}
}

public enum MediaDecryptionError: Error, Equatable, Sendable {
	case fileEncSHA256Mismatch
	case missingAuthenticationCode
	case authenticationCodeMismatch
	case fileSHA256Mismatch
	case aesCBCDecryptionFailed(Int32)
}

private extension Data {
	func prefixData(_ count: Int) -> Data {
		Data(prefix(count))
	}
}
