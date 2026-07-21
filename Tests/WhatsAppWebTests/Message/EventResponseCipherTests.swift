import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Event response cipher")
struct EventResponseCipherTests {
	@Test("encrypts event responses with Baileys-compatible key derivation")
	func encryptsEventResponsesWithBaileysCompatibleKeyDerivation() throws {
		let cipher = EventResponseCipher(ivGenerator: {
			try Data(hexString: "202122232425262728292a2b")
		})
		let response = OutgoingEventResponseContent(
			response: .going,
			timestampMilliseconds: 1_800_000_123_456,
			extraGuestCount: 2
		)

		let encrypted = try cipher.encrypt(
			response,
			eventMessageID: "3EB0EVENTCREATE",
			eventCreatorJID: "111@s.whatsapp.net",
			responderJID: "222@s.whatsapp.net",
			eventMessageSecret: try Data(hexString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
		)

		#expect(encrypted.encIv == (try Data(hexString: "202122232425262728292a2b")))
		#expect(encrypted.encPayload == (try Data(hexString: "e5e06ccecdde6bc10ab15672664cd3251c67a7a96bb87b79ee34ea")))
	}

	@Test("decrypts encrypted event responses with Baileys-compatible key derivation")
	func decryptsEncryptedEventResponsesWithBaileysCompatibleKeyDerivation() throws {
		let cipher = EventResponseCipher()
		let decrypted = try cipher.decrypt(
			ReceivedEncryptedEventResponseContent(
				eventCreationMessageKey: nil,
				encryptedPayload: try Data(hexString: "e5e06ccecdde6bc10ab15672664cd3251c67a7a96bb87b79ee34ea"),
				encryptedIV: try Data(hexString: "202122232425262728292a2b")
			),
			eventMessageID: "3EB0EVENTCREATE",
			eventCreatorJID: "111@s.whatsapp.net",
			responderJID: "222@s.whatsapp.net",
			eventMessageSecret: try Data(hexString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
		)

		#expect(decrypted == ReceivedEventResponseContent(
			response: .going,
			timestampMilliseconds: 1_800_000_123_456,
			extraGuestCount: 2
		))
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw EventResponseCipherTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}
}

private enum EventResponseCipherTestError: Error {
	case invalidHex
}
