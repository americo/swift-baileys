import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("AES GCM cipher")
struct AESGCMCipherTests {
	@Test("encrypts with Node-compatible AES-256-GCM")
	func encryptsWithNodeCompatibleAES256GCM() throws {
		let ciphertext = try AESGCMCipher.encrypt(plaintext, key: key, iv: iv, additionalAuthenticatedData: aad)

		#expect(ciphertext == expectedCiphertext)
	}

	@Test("decrypts Node-compatible AES-256-GCM ciphertext with suffixed tag")
	func decryptsNodeCompatibleAES256GCMCiphertextWithSuffixedTag() throws {
		let decrypted = try AESGCMCipher.decrypt(expectedCiphertext, key: key, iv: iv, additionalAuthenticatedData: aad)

		#expect(decrypted == plaintext)
	}

	@Test("rejects invalid key length")
	func rejectsInvalidKeyLength() throws {
		#expect(throws: AESGCMCipherError.invalidKeyLength) {
			try AESGCMCipher.encrypt(plaintext, key: Data(repeating: 0, count: 31), iv: iv, additionalAuthenticatedData: aad)
		}
	}

	@Test("rejects ciphertexts shorter than the GCM tag")
	func rejectsCiphertextsShorterThanTheGCMTag() throws {
		#expect(throws: AESGCMCipherError.invalidCiphertext) {
			try AESGCMCipher.decrypt(Data(repeating: 0, count: 15), key: key, iv: iv, additionalAuthenticatedData: aad)
		}
	}

	private let key = try! hexData("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
	private let iv = try! hexData("101112131415161718191a1b")
	private let aad = try! hexData("53776966744261696c657973204145532047434d20414144")
	private let plaintext = try! hexData("53776966744261696c657973204145532047434d2066697874757265")
	private let expectedCiphertext = try! hexData("2e89f1703d8b5bdaa610716e2f382c00f7170d433ba43ec9938c90020e096e587fe4e2742a43151a6e8f805a")
}
