import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Noise handshake state")
struct NoiseHandshakeStateTests {
	@Test("authenticates handshake data into the transcript hash")
	func authenticatesHandshakeData() throws {
		var handshake = NoiseHandshakeState()

		handshake.authenticate(try Data(hexString: "57410102"))
		handshake.authenticate(try Data(hexString: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"))

		#expect(handshake.hash.hexString == "a96e1f4f118133dbee24bee9130db8bbfde8cbe92802cc8adffadc87b938a20f")
	}

	@Test("encrypts with the transcript hash as associated data")
	func encryptsWithTranscriptHash() throws {
		var handshake = NoiseHandshakeState()
		handshake.authenticate(try Data(hexString: "57410102"))
		handshake.authenticate(try Data(hexString: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"))

		let ciphertext = try handshake.encrypt(Data("client-noise-test".utf8))

		#expect(ciphertext.hexString == "417b7922ba607779696cdaf7c7bba2e1a95312667efce70bf824ab495553fd7c43")
		#expect(handshake.hash.hexString == "04288190a8643f8439be512c81afcf52bcc51da525a5042a41d67ff47be9cfeb")
	}

	@Test("mixes key material and resets the handshake cipher counter")
	func mixesKeyMaterialAndResetsCounter() throws {
		var handshake = NoiseHandshakeState()
		handshake.authenticate(try Data(hexString: "57410102"))
		handshake.authenticate(try Data(hexString: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"))
		_ = try handshake.encrypt(Data("client-noise-test".utf8))

		try handshake.mixIntoKey(try Data(hexString: "0102030405060708090a0b0c0d0e0f10"))

		#expect(handshake.salt.hexString == "d3f09bb9fc689bb7cd34ad6f5c5f443e79f959c539dbd8f6816312b503072c6e")
		#expect(handshake.encryptionKey.hexString == "55758be177f1d040e21d2a81ebde4250073734505394bb48d01e41f5d9abb4b0")
	}

	@Test("decrypts with the transcript hash as associated data")
	func decryptsWithTranscriptHash() throws {
		var handshake = NoiseHandshakeState()
		handshake.authenticate(try Data(hexString: "57410102"))
		handshake.authenticate(try Data(hexString: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"))
		_ = try handshake.encrypt(Data("client-noise-test".utf8))
		try handshake.mixIntoKey(try Data(hexString: "0102030405060708090a0b0c0d0e0f10"))

		let plaintext = try handshake.decrypt(
			try Data(hexString: "63eecc33df95287b01adabf164563600cf85e163e0c24ba68c384865a1d2bbcfd3")
		)

		#expect(plaintext == Data("client-noise-test".utf8))
		#expect(handshake.hash.hexString == "9d1f770a0c8205274121fc54aa5f137219760a072feca9a24325f29e339ca7db")
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw NoiseHandshakeStateTestError.invalidHex
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

private enum NoiseHandshakeStateTestError: Error {
	case invalidHex
}
