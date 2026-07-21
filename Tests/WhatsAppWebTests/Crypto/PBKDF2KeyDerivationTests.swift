import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("PBKDF2 key derivation")
struct PBKDF2KeyDerivationTests {
	@Test("derives SHA-256 keys with the Baileys pairing-code parameters")
	func derivesSHA256KeysWithBaileysPairingCodeParameters() throws {
		let key = try PBKDF2KeyDerivation.sha256(
			password: Data("ABCDEFGH".utf8),
			salt: Data(1...32),
			iterations: 2 << 16,
			outputByteCount: 32
		)

		#expect(key == (try hexData("0db7c31840031a03c1d2a47cc93d37c61a780fad51595e41020ad9bdebef360e")))
	}

	@Test("rejects empty output requests")
	func rejectsEmptyOutputRequests() {
		#expect(throws: PBKDF2KeyDerivationError.invalidOutputByteCount) {
			_ = try PBKDF2KeyDerivation.sha256(
				password: Data("ABCDEFGH".utf8),
				salt: Data(1...32),
				iterations: 2 << 16,
				outputByteCount: 0
			)
		}
	}
}
