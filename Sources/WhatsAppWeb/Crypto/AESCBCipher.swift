import CommonCrypto
import Foundation

public enum AESCBCipher {
	public static func encrypt(_ plaintext: Data, key: Data, iv: Data) throws -> Data {
		try crypt(plaintext, key: key, iv: iv, operation: CCOperation(kCCEncrypt))
	}

	public static func decrypt(_ ciphertext: Data, key: Data, iv: Data) throws -> Data {
		try crypt(ciphertext, key: key, iv: iv, operation: CCOperation(kCCDecrypt))
	}

	public static func encryptPrefixedIV(_ plaintext: Data, key: Data, iv: Data) throws -> Data {
		iv + (try encrypt(plaintext, key: key, iv: iv))
	}

	public static func decryptPrefixedIV(_ encrypted: Data, key: Data) throws -> Data {
		guard encrypted.count > kCCBlockSizeAES128 else {
			throw AESCBCipherError.invalidCiphertext
		}

		return try decrypt(
			Data(encrypted.dropFirst(kCCBlockSizeAES128)),
			key: key,
			iv: Data(encrypted.prefix(kCCBlockSizeAES128))
		)
	}

	private static func crypt(_ input: Data, key: Data, iv: Data, operation: CCOperation) throws -> Data {
		guard key.count == kCCKeySizeAES256 else {
			throw AESCBCipherError.invalidKeyLength
		}
		guard iv.count == kCCBlockSizeAES128 else {
			throw AESCBCipherError.invalidIVLength
		}

		let outputCapacity = input.count + kCCBlockSizeAES128
		var output = Data(count: outputCapacity)
		var outputLength = 0

		let status = output.withUnsafeMutableBytes { outputBuffer in
			input.withUnsafeBytes { inputBuffer in
				key.withUnsafeBytes { keyBuffer in
					iv.withUnsafeBytes { ivBuffer in
						CCCrypt(
							operation,
							CCAlgorithm(kCCAlgorithmAES),
							CCOptions(kCCOptionPKCS7Padding),
							keyBuffer.baseAddress,
							key.count,
							ivBuffer.baseAddress,
							inputBuffer.baseAddress,
							input.count,
							outputBuffer.baseAddress,
							outputCapacity,
							&outputLength
						)
					}
				}
			}
		}

		guard status == kCCSuccess else {
			throw AESCBCipherError.cryptFailed(status)
		}

		output.removeSubrange(outputLength..<output.count)
		return output
	}
}

public enum AESCBCipherError: Error, Equatable, Sendable {
	case invalidKeyLength
	case invalidIVLength
	case invalidCiphertext
	case cryptFailed(CCCryptorStatus)
}
