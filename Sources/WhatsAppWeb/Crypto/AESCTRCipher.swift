import CommonCrypto
import Foundation

public enum AESCTRCipher {
	public static func encrypt(_ plaintext: Data, key: Data, iv: Data) throws -> Data {
		try crypt(plaintext, key: key, iv: iv, operation: CCOperation(kCCEncrypt))
	}

	public static func decrypt(_ ciphertext: Data, key: Data, iv: Data) throws -> Data {
		try crypt(ciphertext, key: key, iv: iv, operation: CCOperation(kCCDecrypt))
	}

	private static func crypt(_ input: Data, key: Data, iv: Data, operation: CCOperation) throws -> Data {
		guard key.count == kCCKeySizeAES256 else {
			throw AESCTRCipherError.invalidKeyLength
		}

		guard iv.count == kCCBlockSizeAES128 else {
			throw AESCTRCipherError.invalidIVLength
		}

		var cryptor: CCCryptorRef?
		let createStatus = key.withUnsafeBytes { keyBuffer in
			iv.withUnsafeBytes { ivBuffer in
				CCCryptorCreateWithMode(
					operation,
					CCMode(kCCModeCTR),
					CCAlgorithm(kCCAlgorithmAES),
					CCPadding(ccNoPadding),
					ivBuffer.baseAddress,
					keyBuffer.baseAddress,
					key.count,
					nil,
					0,
					0,
					CCModeOptions(kCCModeOptionCTR_BE),
					&cryptor
				)
			}
		}

		guard createStatus == kCCSuccess, let cryptor else {
			throw AESCTRCipherError.cryptorCreationFailed(createStatus)
		}
		defer { CCCryptorRelease(cryptor) }

		let outputCapacity = input.count + kCCBlockSizeAES128
		var output = Data(count: outputCapacity)
		var moved = 0
		let updateStatus = output.withUnsafeMutableBytes { outputBuffer in
			input.withUnsafeBytes { inputBuffer in
				CCCryptorUpdate(
					cryptor,
					inputBuffer.baseAddress,
					input.count,
					outputBuffer.baseAddress,
					outputCapacity,
					&moved
				)
			}
		}

		guard updateStatus == kCCSuccess else {
			throw AESCTRCipherError.cryptorUpdateFailed(updateStatus)
		}

		output.removeSubrange(moved..<output.count)
		return output
	}
}

public enum AESCTRCipherError: Error, Equatable, Sendable {
	case invalidKeyLength
	case invalidIVLength
	case cryptorCreationFailed(CCCryptorStatus)
	case cryptorUpdateFailed(CCCryptorStatus)
}
