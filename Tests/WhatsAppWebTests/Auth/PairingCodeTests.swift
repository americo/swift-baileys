import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Pairing code")
struct PairingCodeTests {
	@Test("derives pairing code key with Baileys-compatible PBKDF2")
	func derivesPairingCodeKeyWithBaileysCompatiblePBKDF2() throws {
		let salt = Data(1...32)
		let key = try PairingCode.deriveKey(pairingCode: "ABCDEFGH", salt: salt)
		let expected = try hexData("0db7c31840031a03c1d2a47cc93d37c61a780fad51595e41020ad9bdebef360e")

		#expect(key == expected)
	}

	@Test("wraps companion ephemeral public key")
	func wrapsCompanionEphemeralPublicKey() throws {
		let salt = Data(1...32)
		let iv = Data(33...48)
		let publicKey = Data(65...96)

		let wrapped = try PairingCode.wrapCompanionEphemeralPublicKey(
			publicKey,
			pairingCode: "ABCDEFGH",
			salt: salt,
			iv: iv
		)
		let expected = try hexData(
			"0102030405060708090a0b0c0d0e0f10" +
			"1112131415161718191a1b1c1d1e1f20" +
			"2122232425262728292a2b2c2d2e2f30" +
			"f5885140f0df903397e2ec120f148661" +
			"f54712d88988fb5406e83ae82de5f28d"
		)

		#expect(wrapped == expected)
	}

	@Test("unwraps primary ephemeral public key")
	func unwrapsPrimaryEphemeralPublicKey() throws {
		let publicKey = Data(65...96)
		let wrapped = try PairingCode.wrapCompanionEphemeralPublicKey(
			publicKey,
			pairingCode: "ABCDEFGH",
			salt: Data(1...32),
			iv: Data(33...48)
		)

		#expect(try PairingCode.unwrapPrimaryEphemeralPublicKey(wrapped, pairingCode: "ABCDEFGH") == publicKey)
	}

	@Test("encodes random bytes as Crockford pairing code")
	func encodesRandomBytesAsCrockfordPairingCode() {
		#expect(PairingCode.crockfordString(from: Data([0, 1, 2, 3, 4])) == "111H51R5")
	}
}
