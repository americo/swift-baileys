import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("App-state patch cipher")
struct AppStatePatchCipherTests {
	@Test("encrypts values with IV-prefixed AES-CBC like Baileys")
	func encryptsValuesWithIVPrefixedAESCBC() throws {
		let plaintext = try Data(hexString: "00112233445566778899aabbccddeeff")
		let key = try Data(hexString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
		let iv = try Data(hexString: "202122232425262728292a2b2c2d2e2f")

		let encrypted = try AppStatePatchCipher.encryptValue(plaintext, key: key, iv: iv)

		#expect(encrypted == (try Data(hexString: "202122232425262728292a2b2c2d2e2f4bd776c647f6085f20a1467a7d8dde4c106c9d2abc2825c7c77d27dd32b8f9a2")))
		#expect(try AppStatePatchCipher.decryptValue(encrypted, key: key) == plaintext)
	}

	@Test("rejects invalid IV lengths")
	func rejectsInvalidIVLengths() throws {
		#expect(throws: AppStatePatchCipherError.invalidIVLength) {
			try AppStatePatchCipher.encryptValue(
				Data([0x01]),
				key: Data(repeating: 0, count: 32),
				iv: Data(repeating: 0, count: 15)
			)
		}
	}
}

private extension Data {
	init(hexString: String) throws {
		guard hexString.count.isMultiple(of: 2) else {
			throw HexDataError.invalidLength
		}

		var bytes = [UInt8]()
		bytes.reserveCapacity(hexString.count / 2)
		var index = hexString.startIndex
		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw HexDataError.invalidByte
			}
			bytes.append(byte)
			index = next
		}
		self = Data(bytes)
	}
}

private enum HexDataError: Error {
	case invalidLength
	case invalidByte
}
