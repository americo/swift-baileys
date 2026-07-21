import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Noise transport state")
struct NoiseTransportStateTests {
	@Test("encrypts with AES-GCM and appends the authentication tag like Baileys")
	func encryptsWithAESGCMTagSuffix() throws {
		var transport = NoiseTransportState(
			encryptionKey: Data(0..<32),
			decryptionKey: Data(0..<32)
		)

		let first = try transport.encrypt(Data("hello".utf8))
		let second = try transport.encrypt(Data("hello".utf8))

		#expect(first.hexString == "66d9d9b2da0e0c4679f3a82524f5e0499271e16f30")
		#expect(second.hexString == "7db3d3902b668586cf2edee656e1ea5fe36d7bf3d1")
		#expect(first != second)
	}

	@Test("decrypts AES-GCM ciphertexts using the read counter")
	func decryptsWithReadCounter() throws {
		var transport = NoiseTransportState(
			encryptionKey: Data(0..<32),
			decryptionKey: Data(0..<32)
		)

		let first = try Data(hexString: "66d9d9b2da0e0c4679f3a82524f5e0499271e16f30")
		let second = try Data(hexString: "7db3d3902b668586cf2edee656e1ea5fe36d7bf3d1")

		#expect(try transport.decrypt(first) == Data("hello".utf8))
		#expect(try transport.decrypt(second) == Data("hello".utf8))
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw NoiseTransportStateTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}

	var hexString: String {
		map { String(format: "%02x", $0) }.joined()
	}
}

private enum NoiseTransportStateTestError: Error {
	case invalidHex
}
