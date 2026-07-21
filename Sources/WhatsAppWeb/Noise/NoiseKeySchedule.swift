import CryptoKit
import Foundation

public struct NoiseTransportKeys: Equatable, Sendable {
	public let write: Data
	public let read: Data
}

public struct NoiseKeySchedule: Sendable {
	public private(set) var salt: Data
	public private(set) var encryptionKey: Data
	public private(set) var decryptionKey: Data

	public init() {
		let mode = Data("Noise_XX_25519_AESGCM_SHA256\0\0\0\0".utf8)
		let initial = mode.count == 32 ? mode : Data(SHA256.hash(data: mode))
		self.salt = initial
		self.encryptionKey = initial
		self.decryptionKey = initial
	}

	public mutating func mixIntoKey(_ input: Data) throws {
		let expanded = try hkdf(input: input, salt: salt, byteCount: 64)
		salt = expanded.prefixData(32)
		encryptionKey = expanded.suffixData(from: 32)
		decryptionKey = encryptionKey
	}

	public func deriveTransportKeys() throws -> NoiseTransportKeys {
		let expanded = try hkdf(input: Data(), salt: salt, byteCount: 64)
		return NoiseTransportKeys(
			write: expanded.prefixData(32),
			read: expanded.suffixData(from: 32)
		)
	}

	private func hkdf(input: Data, salt: Data, byteCount: Int) throws -> Data {
		let key = HKDF<SHA256>.deriveKey(
			inputKeyMaterial: SymmetricKey(data: input),
			salt: salt,
			info: Data(),
			outputByteCount: byteCount
		)

		return key.withUnsafeBytes { Data($0) }
	}
}

private extension Data {
	func prefixData(_ count: Int) -> Data {
		Data(prefix(count))
	}

	func suffixData(from index: Int) -> Data {
		Data(dropFirst(index))
	}
}
