import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("AES CTR cipher")
struct AESCTRCipherTests {
	@Test("encrypts with Node-compatible AES-256-CTR")
	func encryptsWithNodeCompatibleAES256CTR() throws {
		let ciphertext = try AESCTRCipher.encrypt(plaintext, key: key, iv: iv)

		#expect(ciphertext == expectedCiphertext)
	}

	@Test("decrypts Node-compatible AES-256-CTR ciphertext")
	func decryptsNodeCompatibleAES256CTRCiphertext() throws {
		let decrypted = try AESCTRCipher.decrypt(expectedCiphertext, key: key, iv: iv)

		#expect(decrypted == plaintext)
	}

	@Test("roundtrips empty payloads")
	func roundtripsEmptyPayloads() throws {
		let ciphertext = try AESCTRCipher.encrypt(Data(), key: key, iv: iv)

		#expect(ciphertext.isEmpty)
		#expect(try AESCTRCipher.decrypt(ciphertext, key: key, iv: iv).isEmpty)
	}

	@Test("rejects invalid key length")
	func rejectsInvalidKeyLength() throws {
		#expect(throws: AESCTRCipherError.invalidKeyLength) {
			try AESCTRCipher.encrypt(plaintext, key: Data(repeating: 0, count: 31), iv: iv)
		}
	}

	@Test("rejects invalid IV length")
	func rejectsInvalidIVLength() throws {
		#expect(throws: AESCTRCipherError.invalidIVLength) {
			try AESCTRCipher.decrypt(expectedCiphertext, key: key, iv: Data(repeating: 0, count: 15))
		}
	}

	private let key = try! hexData("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
	private let iv = try! hexData("101112131415161718191a1b1c1d1e1f")
	private let plaintext = try! hexData("53776966744261696c65797320414553204354522066697874757265")
	private let expectedCiphertext = try! hexData("bab486ecc676328f9c11e5a516a6edddd9821fc8dbf2ad99c287e226")
}
