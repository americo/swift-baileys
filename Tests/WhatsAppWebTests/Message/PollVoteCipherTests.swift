import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Poll vote cipher")
struct PollVoteCipherTests {
	@Test("encrypts poll votes with Baileys-compatible key derivation")
	func encryptsPollVotesWithBaileysCompatibleKeyDerivation() throws {
		let cipher = PollVoteCipher(ivGenerator: {
			try Data(hexString: "202122232425262728292a2b")
		})

		let encrypted = try cipher.encrypt(
			selectedOptionHashes: [
				try Data(hexString: "010203"),
				try Data(hexString: "aabb")
			],
			pollMessageID: "3EB0POLLCREATE",
			pollCreatorJID: "111@s.whatsapp.net",
			voterJID: "222@s.whatsapp.net",
			pollEncKey: try Data(hexString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
		)

		#expect(encrypted.encIv == (try Data(hexString: "202122232425262728292a2b")))
		#expect(encrypted.encPayload == (try Data(hexString: "8d003bd1292aa2d60daace61c471b4a1cbcaec660f18c18fb9")))
	}

	@Test("decrypts poll votes with Baileys-compatible key derivation")
	func decryptsPollVotesWithBaileysCompatibleKeyDerivation() throws {
		let cipher = PollVoteCipher()
		var encrypted = Proto_Message.PollEncValue()
		encrypted.encPayload = try Data(hexString: "8d003bd1292aa2d60daace61c471b4a1cbcaec660f18c18fb9")
		encrypted.encIv = try Data(hexString: "202122232425262728292a2b")

		let selectedOptionHashes = try cipher.decrypt(
			encrypted,
			pollMessageID: "3EB0POLLCREATE",
			pollCreatorJID: "111@s.whatsapp.net",
			voterJID: "222@s.whatsapp.net",
			pollEncKey: try Data(hexString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
		)

		#expect(selectedOptionHashes == [
			try Data(hexString: "010203"),
			try Data(hexString: "aabb")
		])
	}

	@Test("throws for missing encrypted poll vote payload")
	func throwsForMissingEncryptedPollVotePayload() {
		let cipher = PollVoteCipher()
		var encrypted = Proto_Message.PollEncValue()
		encrypted.encIv = Data(repeating: 0, count: 12)

		#expect(throws: PollVoteCipherError.missingEncryptedPayload) {
			try cipher.decrypt(
				encrypted,
				pollMessageID: "poll",
				pollCreatorJID: "creator@s.whatsapp.net",
				voterJID: "voter@s.whatsapp.net",
				pollEncKey: Data(repeating: 0, count: 32)
			)
		}
	}

	@Test("throws for invalid encrypted poll vote payload length")
	func throwsForInvalidEncryptedPollVotePayloadLength() {
		let cipher = PollVoteCipher()
		var encrypted = Proto_Message.PollEncValue()
		encrypted.encPayload = Data([0x01])
		encrypted.encIv = Data(repeating: 0, count: 12)

		#expect(throws: PollVoteCipherError.invalidEncryptedPayloadLength) {
			try cipher.decrypt(
				encrypted,
				pollMessageID: "poll",
				pollCreatorJID: "creator@s.whatsapp.net",
				voterJID: "voter@s.whatsapp.net",
				pollEncKey: Data(repeating: 0, count: 32)
			)
		}
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw PollVoteCipherTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}
}

private enum PollVoteCipherTestError: Error {
	case invalidHex
}
