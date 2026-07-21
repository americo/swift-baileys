import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Registration ID generator")
struct RegistrationIDGeneratorTests {
	@Test("generates Baileys registration id from little-endian random bytes")
	func generatesBaileysRegistrationIDFromLittleEndianRandomBytes() throws {
		let registrationID = try RegistrationIDGenerator.generate { count in
			#expect(count == 2)
			return Data([0x02, 0x01])
		}

		#expect(registrationID == 258)
	}

	@Test("masks generated registration id to fourteen bits")
	func masksGeneratedRegistrationIDToFourteenBits() throws {
		let registrationID = try RegistrationIDGenerator.generate { _ in Data([0xff, 0xff]) }

		#expect(registrationID == 16_383)
	}

	@Test("rejects invalid random byte count")
	func rejectsInvalidRandomByteCount() {
		#expect(throws: RegistrationIDGeneratorError.invalidRandomByteCount) {
			try RegistrationIDGenerator.generate { _ in Data([0x01]) }
		}
	}
}
