import CommonCrypto
import Foundation

enum AppStatePatchCipher {
	static func encryptValue(_ plaintext: Data, key: Data, iv: Data) throws -> Data {
		guard iv.count == kCCBlockSizeAES128 else {
			throw AppStatePatchCipherError.invalidIVLength
		}

		let outputCapacity = plaintext.count + kCCBlockSizeAES128
		var output = Data(count: outputCapacity)
		var outputLength = 0

		let status = output.withUnsafeMutableBytes { outputBuffer in
			plaintext.withUnsafeBytes { plaintextBuffer in
				key.withUnsafeBytes { keyBuffer in
					iv.withUnsafeBytes { ivBuffer in
						CCCrypt(
							CCOperation(kCCEncrypt),
							CCAlgorithm(kCCAlgorithmAES),
							CCOptions(kCCOptionPKCS7Padding),
							keyBuffer.baseAddress,
							key.count,
							ivBuffer.baseAddress,
							plaintextBuffer.baseAddress,
							plaintext.count,
							outputBuffer.baseAddress,
							outputCapacity,
							&outputLength
						)
					}
				}
			}
		}

		guard status == kCCSuccess else {
			throw AppStatePatchCipherError.encryptionFailed(status)
		}

		output.removeSubrange(outputLength..<output.count)
		return iv + output
	}

	static func decryptValue(_ encryptedValue: Data, key: Data) throws -> Data {
		guard encryptedValue.count > kCCBlockSizeAES128 else {
			throw AppStatePatchCipherError.invalidEncryptedValueLength
		}

		let iv = encryptedValue.prefix(kCCBlockSizeAES128)
		let ciphertext = encryptedValue.dropFirst(kCCBlockSizeAES128)
		let outputCapacity = ciphertext.count
		var output = Data(count: outputCapacity)
		var outputLength = 0

		let status = output.withUnsafeMutableBytes { outputBuffer in
			ciphertext.withUnsafeBytes { ciphertextBuffer in
				key.withUnsafeBytes { keyBuffer in
					iv.withUnsafeBytes { ivBuffer in
						CCCrypt(
							CCOperation(kCCDecrypt),
							CCAlgorithm(kCCAlgorithmAES),
							CCOptions(kCCOptionPKCS7Padding),
							keyBuffer.baseAddress,
							key.count,
							ivBuffer.baseAddress,
							ciphertextBuffer.baseAddress,
							ciphertext.count,
							outputBuffer.baseAddress,
							outputCapacity,
							&outputLength
						)
					}
				}
			}
		}

		guard status == kCCSuccess else {
			throw AppStatePatchCipherError.decryptionFailed(status)
		}

		output.removeSubrange(outputLength..<output.count)
		return output
	}
}

enum AppStatePatchCipherError: Error, Equatable, Sendable {
	case invalidIVLength
	case invalidEncryptedValueLength
	case encryptionFailed(CCCryptorStatus)
	case decryptionFailed(CCCryptorStatus)
}
