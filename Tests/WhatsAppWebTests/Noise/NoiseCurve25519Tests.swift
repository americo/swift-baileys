import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Noise Curve25519")
struct NoiseCurve25519Tests {
	@Test("derives RFC 7748 X25519 shared secret")
	func derivesRFC7748SharedSecret() throws {
		let alicePrivate = try Data(hexString: "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
		let bobPublic = try Data(hexString: "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")

		let sharedSecret = try NoiseCurve25519.sharedSecret(
			privateKey: alicePrivate,
			publicKey: bobPublic
		)

		#expect(sharedSecret.hexString == "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742")
	}

	@Test("derives matching public key from RFC 7748 private key")
	func derivesPublicKey() throws {
		let alicePrivate = try Data(hexString: "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")

		let publicKey = try NoiseCurve25519.publicKey(privateKey: alicePrivate)

		#expect(publicKey.hexString == "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw NoiseCurve25519TestError.invalidHex
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

private enum NoiseCurve25519TestError: Error {
	case invalidHex
}
