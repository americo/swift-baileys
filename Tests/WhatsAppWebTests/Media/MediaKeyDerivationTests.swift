import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Media key derivation")
struct MediaKeyDerivationTests {
	@Test("derives image media keys matching Baileys")
	func derivesImageMediaKeysMatchingBaileys() throws {
		let mediaKey = Data((0..<32).map(UInt8.init))
		let expectedIV = try Data(hexString: "aa6a127218397cbd2383e4ccf7176a79")
		let expectedCipherKey = try Data(hexString: "008c9aea9b7c5d81eb56b3f530f87d42dcc92d27b11ad6b5bd66f0560d0d8c46")
		let expectedMACKey = try Data(hexString: "91d09ffec108833c1699574c52657923fb6e3e161d9698bc6b3a05fbc508a515")

		let keys = try MediaKeyDerivation.deriveKeys(from: mediaKey, mediaType: .image)

		#expect(keys.iv == expectedIV)
		#expect(keys.cipherKey == expectedCipherKey)
		#expect(keys.macKey == expectedMACKey)
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw MediaKeyDerivationTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}
}

private enum MediaKeyDerivationTestError: Error {
	case invalidHex
}
