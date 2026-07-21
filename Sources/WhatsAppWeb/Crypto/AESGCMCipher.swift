import CryptoKit
import Foundation

public enum AESGCMCipher {
	public static func encrypt(
		_ plaintext: Data,
		key: Data,
		iv: Data,
		additionalAuthenticatedData: Data
	) throws -> Data {
		guard key.count == 32 else {
			throw AESGCMCipherError.invalidKeyLength
		}

		let box = try AES.GCM.seal(
			plaintext,
			using: SymmetricKey(data: key),
			nonce: AES.GCM.Nonce(data: iv),
			authenticating: additionalAuthenticatedData
		)
		return box.ciphertext + box.tag
	}

	public static func decrypt(
		_ ciphertext: Data,
		key: Data,
		iv: Data,
		additionalAuthenticatedData: Data
	) throws -> Data {
		guard key.count == 32 else {
			throw AESGCMCipherError.invalidKeyLength
		}
		guard ciphertext.count >= 16 else {
			throw AESGCMCipherError.invalidCiphertext
		}

		let tagStart = ciphertext.index(ciphertext.endIndex, offsetBy: -16)
		let box = try AES.GCM.SealedBox(
			nonce: AES.GCM.Nonce(data: iv),
			ciphertext: Data(ciphertext[..<tagStart]),
			tag: Data(ciphertext[tagStart...])
		)
		return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: additionalAuthenticatedData)
	}
}

public enum AESGCMCipherError: Error, Equatable, Sendable {
	case invalidKeyLength
	case invalidCiphertext
}
