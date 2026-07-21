import CommonCrypto
import Foundation

public enum PBKDF2KeyDerivation {
	public static func sha256(password: Data, salt: Data, iterations: UInt32, outputByteCount: Int) throws -> Data {
		guard outputByteCount > 0 else {
			throw PBKDF2KeyDerivationError.invalidOutputByteCount
		}

		var key = Data(count: outputByteCount)
		let status = key.withUnsafeMutableBytes { keyBuffer in
			password.withUnsafeBytes { passwordBuffer in
				salt.withUnsafeBytes { saltBuffer in
					CCKeyDerivationPBKDF(
						CCPBKDFAlgorithm(kCCPBKDF2),
						passwordBuffer.bindMemory(to: Int8.self).baseAddress,
						password.count,
						saltBuffer.bindMemory(to: UInt8.self).baseAddress,
						salt.count,
						CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
						iterations,
						keyBuffer.bindMemory(to: UInt8.self).baseAddress,
						outputByteCount
					)
				}
			}
		}

		guard status == kCCSuccess else {
			throw PBKDF2KeyDerivationError.derivationFailed(status)
		}

		return key
	}
}

public enum PBKDF2KeyDerivationError: Error, Equatable, Sendable {
	case invalidOutputByteCount
	case derivationFailed(CCStatus)
}
