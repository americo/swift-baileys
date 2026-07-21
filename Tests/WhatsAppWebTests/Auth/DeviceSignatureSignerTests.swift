import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Device signature signer")
struct DeviceSignatureSignerTests {
	@Test("matches libsignal curve signature fixture")
	func matchesLibsignalCurveSignatureFixture() throws {
		let signer = LibSignalDeviceSignatureSigner()
		let signature = try signer.sign(
			privateKey: try Data(hexString: "1111111111111111111111111111111111111111111111111111111111111111"),
			message: try Data(hexString:
				"06010801100218032000280065666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838407a37cbc142093c8b755dc1b10e86cb426374ad16aa853ed0bdfc0b2b86d1c7c"
			)
		)

		let expectedSignature = try Data(hexString:
			"9d54ee3885b993985afa8df0b3fcd9502e4a598c1f268cddb4c6dc859f316e4827b6cbddb79d6a2a88db8bed8603ea10ea21e1936824004b7e3c1ef302be1181"
		)
		#expect(signature == expectedSignature)
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw DeviceSignatureSignerTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}
}

private enum DeviceSignatureSignerTestError: Error {
	case invalidHex
}
