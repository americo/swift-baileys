import CommonCrypto
import Foundation

public enum PairingCode {
	public static let keyDerivationIterations: UInt32 = 2 << 16
	public static let keyDerivationOutputByteCount = 32

	public static func crockfordString(from data: Data) -> String {
		ByteCrockfordEncoder.encode(data)
	}

	public static func deriveKey(pairingCode: String, salt: Data) throws -> Data {
		do {
			return try PBKDF2KeyDerivation.sha256(
				password: Data(pairingCode.utf8),
				salt: salt,
				iterations: keyDerivationIterations,
				outputByteCount: keyDerivationOutputByteCount
			)
		} catch PBKDF2KeyDerivationError.derivationFailed(let status) {
			throw PairingCodeError.keyDerivationFailed(status)
		} catch {
			throw error
		}
	}

	public static func wrapCompanionEphemeralPublicKey(
		_ publicKey: Data,
		pairingCode: String,
		salt: Data,
		iv: Data
	) throws -> Data {
		let key = try deriveKey(pairingCode: pairingCode, salt: salt)
		do {
			return salt + iv + (try AESCTRCipher.encrypt(publicKey, key: key, iv: iv))
		} catch AESCTRCipherError.invalidKeyLength, AESCTRCipherError.invalidIVLength {
			throw PairingCodeError.aesCTRCreationFailed(CCCryptorStatus(kCCParamError))
		} catch AESCTRCipherError.cryptorCreationFailed(let status) {
			throw PairingCodeError.aesCTRCreationFailed(status)
		} catch AESCTRCipherError.cryptorUpdateFailed(let status) {
			throw PairingCodeError.aesCTRUpdateFailed(status)
		}
	}

	public static func unwrapPrimaryEphemeralPublicKey(_ wrappedKey: Data, pairingCode: String) throws -> Data {
		guard wrappedKey.count > 48 else {
			throw PairingCodeError.invalidWrappedKey
		}

		let salt = Data(wrappedKey.prefix(32))
		let iv = Data(wrappedKey.dropFirst(32).prefix(16))
		let ciphertext = Data(wrappedKey.dropFirst(48))
		let key = try deriveKey(pairingCode: pairingCode, salt: salt)
		do {
			return try AESCTRCipher.decrypt(ciphertext, key: key, iv: iv)
		} catch AESCTRCipherError.invalidKeyLength, AESCTRCipherError.invalidIVLength {
			throw PairingCodeError.aesCTRCreationFailed(CCCryptorStatus(kCCParamError))
		} catch AESCTRCipherError.cryptorCreationFailed(let status) {
			throw PairingCodeError.aesCTRCreationFailed(status)
		} catch AESCTRCipherError.cryptorUpdateFailed(let status) {
			throw PairingCodeError.aesCTRUpdateFailed(status)
		}
	}
}

public enum PairingCodeError: Error, Equatable, Sendable {
	case invalidCustomCodeLength
	case invalidRandomByteCount
	case invalidWrappedKey
	case keyDerivationFailed(CCStatus)
	case aesCTRCreationFailed(CCCryptorStatus)
	case aesCTRUpdateFailed(CCCryptorStatus)
}
