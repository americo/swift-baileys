import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Signal public key formatting")
struct SignalPublicKeyTests {
	@Test("prefixes raw Curve25519 public keys with key bundle type")
	func prefixesRawCurve25519PublicKeysWithKeyBundleType() throws {
		let raw = Data(repeating: 0x11, count: 32)

		#expect(try SignalPublicKey.format(raw) == Data([0x05]) + raw)
	}

	@Test("preserves already formatted Signal public keys")
	func preservesAlreadyFormattedSignalPublicKeys() throws {
		let formatted = Data([0x05]) + Data(repeating: 0x22, count: 32)

		#expect(try SignalPublicKey.format(formatted) == formatted)
	}

	@Test("preserves nonstandard 33-byte public keys like Baileys")
	func preservesNonstandard33BytePublicKeysLikeBaileys() throws {
		let formatted = Data([0x04]) + Data(repeating: 0x33, count: 32)

		#expect(try SignalPublicKey.format(formatted) == formatted)
	}

	@Test("rejects unsupported public key lengths")
	func rejectsUnsupportedPublicKeyLengths() throws {
		#expect(throws: SignalPublicKeyError.invalidKeyMaterial) {
			try SignalPublicKey.format(Data(repeating: 0x44, count: 31))
		}
		#expect(throws: SignalPublicKeyError.invalidKeyMaterial) {
			try SignalPublicKey.format(Data(repeating: 0x66, count: 34))
		}
	}

	@Test("extracts raw Curve25519 public keys from Signal public keys")
	func extractsRawCurve25519PublicKeysFromSignalPublicKeys() {
		let raw = Data(repeating: 0x55, count: 32)

		#expect(SignalPublicKey.curve25519PublicKey(from: Data([0x05]) + raw) == raw)
		#expect(SignalPublicKey.curve25519PublicKey(from: raw) == nil)
	}
}
