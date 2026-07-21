import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("AES CBC cipher")
struct AESCBCipherTests {
	@Test("encrypts with Node-compatible AES-256-CBC")
	func encryptsWithNodeCompatibleAES256CBC() throws {
		let ciphertext = try AESCBCipher.encrypt(plaintext, key: key, iv: iv)

		#expect(ciphertext == expectedCiphertext)
	}

	@Test("decrypts Node-compatible AES-256-CBC ciphertext")
	func decryptsNodeCompatibleAES256CBCCiphertext() throws {
		let decrypted = try AESCBCipher.decrypt(expectedCiphertext, key: key, iv: iv)

		#expect(decrypted == plaintext)
	}

	@Test("encrypts and decrypts IV-prefixed payloads")
	func encryptsAndDecryptsIVPrefixedPayloads() throws {
		let encrypted = try AESCBCipher.encryptPrefixedIV(plaintext, key: key, iv: iv)

		#expect(encrypted == expectedPrefixedCiphertext)
		#expect(try AESCBCipher.decryptPrefixedIV(encrypted, key: key) == plaintext)
	}

	@Test("rejects invalid inputs")
	func rejectsInvalidInputs() throws {
		#expect(throws: AESCBCipherError.invalidKeyLength) {
			try AESCBCipher.encrypt(plaintext, key: Data(repeating: 0, count: 31), iv: iv)
		}
		#expect(throws: AESCBCipherError.invalidIVLength) {
			try AESCBCipher.decrypt(expectedCiphertext, key: key, iv: Data(repeating: 0, count: 15))
		}
		#expect(throws: AESCBCipherError.invalidCiphertext) {
			try AESCBCipher.decryptPrefixedIV(Data(repeating: 0, count: 16), key: key)
		}
	}

	private let key = try! hexData("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
	private let iv = try! hexData("202122232425262728292a2b2c2d2e2f")
	private let plaintext = try! hexData("53776966744261696c65797320414553204342432066697874757265")
	private let expectedCiphertext = try! hexData("70433fa0a451ca00a908ec0e4c1dbf28209db1e3b31034364b157c37297c8d10")
	private let expectedPrefixedCiphertext = try! hexData("202122232425262728292a2b2c2d2e2f70433fa0a451ca00a908ec0e4c1dbf28209db1e3b31034364b157c37297c8d10")
}
