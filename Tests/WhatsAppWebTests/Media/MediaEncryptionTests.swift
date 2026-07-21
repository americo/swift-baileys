import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Media encryption")
struct MediaEncryptionTests {
	@Test("encrypts image payloads matching Baileys")
	func encryptsImagePayloadsMatchingBaileys() throws {
		let mediaKey = try Data(hexString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
		let plaintext = Data("swift baileys media fixture".utf8)
		let expectedEncryptedFile = try Data(hexString: "3a3018e9b6b731f67593006398f95c50dc0d3938ce1c2652b64845c2c9eeb87b5ecae5e287aaeebc57b1")
		let expectedMAC = try Data(hexString: "5ecae5e287aaeebc57b1")
		let expectedFileSHA256 = try Data(hexString: "fe07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce")
		let expectedFileEncSHA256 = try Data(hexString: "00f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d03")

		let encrypted = try MediaEncryption.encrypt(plaintext, mediaKey: mediaKey, mediaType: .image)

		#expect(encrypted.encryptedFile == expectedEncryptedFile)
		#expect(encrypted.mac == expectedMAC)
		#expect(encrypted.fileSha256 == expectedFileSHA256)
		#expect(encrypted.fileEncSha256 == expectedFileEncSHA256)
		#expect(encrypted.fileLength == plaintext.count)
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw MediaEncryptionTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}
}

private enum MediaEncryptionTestError: Error {
	case invalidHex
}
