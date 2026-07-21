import CryptoKit
import Foundation

public enum NoiseTransportStateError: Error {
	case invalidCiphertext
}

public struct NoiseTransportState: Sendable {
	private var readCounter = 0
	private var writeCounter = 0
	private let encryptionKey: SymmetricKey
	private let decryptionKey: SymmetricKey

	public init(encryptionKey: Data, decryptionKey: Data) {
		self.encryptionKey = SymmetricKey(data: encryptionKey)
		self.decryptionKey = SymmetricKey(data: decryptionKey)
	}

	public mutating func encrypt(_ plaintext: Data) throws -> Data {
		let currentCounter = writeCounter
		writeCounter += 1

		let sealedBox = try AES.GCM.seal(
			plaintext,
			using: encryptionKey,
			nonce: nonce(counter: currentCounter),
			authenticating: Data()
		)

		return sealedBox.ciphertext + sealedBox.tag
	}

	public mutating func decrypt(_ ciphertext: Data) throws -> Data {
		guard ciphertext.count >= 16 else {
			throw NoiseTransportStateError.invalidCiphertext
		}

		let currentCounter = readCounter
		readCounter += 1

		let encryptedData = ciphertext.prefix(ciphertext.count - 16)
		let tag = ciphertext.suffix(16)
		let sealedBox = try AES.GCM.SealedBox(
			nonce: nonce(counter: currentCounter),
			ciphertext: encryptedData,
			tag: tag
		)

		return try AES.GCM.open(sealedBox, using: decryptionKey, authenticating: Data())
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
