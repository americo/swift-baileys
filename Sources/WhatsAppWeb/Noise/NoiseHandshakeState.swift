import CryptoKit
import Foundation

public enum NoiseHandshakeStateError: Error {
	case invalidCiphertext
}

public struct NoiseHandshakeState: Sendable {
	public private(set) var hash: Data
	public var salt: Data {
		keySchedule.salt
	}

	public var encryptionKey: Data {
		keySchedule.encryptionKey
	}

	public var decryptionKey: Data {
		keySchedule.decryptionKey
	}

	private var counter = 0
	private var keySchedule: NoiseKeySchedule

	public init() {
		let schedule = NoiseKeySchedule()
		self.keySchedule = schedule
		self.hash = schedule.salt
	}

	public mutating func authenticate(_ data: Data) {
		hash = Data(SHA256.hash(data: hash + data))
	}

	public mutating func mixIntoKey(_ input: Data) throws {
		try keySchedule.mixIntoKey(input)
		counter = 0
	}

	public mutating func encrypt(_ plaintext: Data) throws -> Data {
		let currentCounter = counter
		counter += 1

		let sealedBox = try AES.GCM.seal(
			plaintext,
			using: SymmetricKey(data: keySchedule.encryptionKey),
			nonce: nonce(counter: currentCounter),
			authenticating: hash
		)
		let ciphertext = sealedBox.ciphertext + sealedBox.tag
		authenticate(ciphertext)
		return ciphertext
	}

	public mutating func decrypt(_ ciphertext: Data) throws -> Data {
		guard ciphertext.count >= 16 else {
			throw NoiseHandshakeStateError.invalidCiphertext
		}

		let currentCounter = counter
		counter += 1

		let encryptedData = ciphertext.prefix(ciphertext.count - 16)
		let tag = ciphertext.suffix(16)
		let sealedBox = try AES.GCM.SealedBox(
			nonce: nonce(counter: currentCounter),
			ciphertext: encryptedData,
			tag: tag
		)
		let plaintext = try AES.GCM.open(
			sealedBox,
			using: SymmetricKey(data: keySchedule.decryptionKey),
			authenticating: hash
		)
		authenticate(ciphertext)
		return plaintext
	}

	public func makeTransportState() throws -> NoiseTransportState {
		let keys = try keySchedule.deriveTransportKeys()
		return NoiseTransportState(encryptionKey: keys.write, decryptionKey: keys.read)
	}

	private func nonce(counter: Int) throws -> AES.GCM.Nonce {
		var bytes = Data(repeating: 0, count: 12)
		bytes[8] = UInt8((counter >> 24) & 0xff)
		bytes[9] = UInt8((counter >> 16) & 0xff)
		bytes[10] = UInt8((counter >> 8) & 0xff)
		bytes[11] = UInt8(counter & 0xff)
		return try AES.GCM.Nonce(data: bytes)
	}
}
