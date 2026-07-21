import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Noise XEdDSA verifier")
struct NoiseXEdDSAVerifierTests {
	@Test("verifies signatures accepted by libsignal curve verification")
	func verifiesLibsignalSignature() throws {
		let verifier = NoiseXEdDSAVerifier()

		let verified = verifier.verify(
			publicKey: try Data(hexString: "8f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f"),
			message: Data("noise-certificate-test".utf8),
			signature: try Data(hexString: "d3184c4e3e74bbf85b4931dd1eb4686c9b240c3576f973ab188c92508dc831d234140fa4b6884622ccca797847c76235570ee0651ca3aa7dcac2f6c8141e700d")
		)

		#expect(verified)
	}

	@Test("rejects modified signatures")
	func rejectsModifiedSignature() throws {
		let verifier = NoiseXEdDSAVerifier()
		var signature = try Data(hexString: "d3184c4e3e74bbf85b4931dd1eb4686c9b240c3576f973ab188c92508dc831d234140fa4b6884622ccca797847c76235570ee0651ca3aa7dcac2f6c8141e700d")
		signature[0] ^= 0x01

		let verified = verifier.verify(
			publicKey: try Data(hexString: "8f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f"),
			message: Data("noise-certificate-test".utf8),
			signature: signature
		)

		#expect(!verified)
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw NoiseXEdDSAVerifierTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}
}

private enum NoiseXEdDSAVerifierTestError: Error {
	case invalidHex
}
