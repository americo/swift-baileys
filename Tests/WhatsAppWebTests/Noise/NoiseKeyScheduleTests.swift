import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Noise key schedule")
struct NoiseKeyScheduleTests {
	@Test("initializes from the WhatsApp Noise mode")
	func initializesFromNoiseMode() {
		let schedule = NoiseKeySchedule()

		#expect(schedule.salt.hexString == "4e6f6973655f58585f32353531395f41455347434d5f53484132353600000000")
		#expect(schedule.encryptionKey == schedule.salt)
		#expect(schedule.decryptionKey == schedule.salt)
	}

	@Test("mixes key material with HKDF-SHA256 like Baileys")
	func mixesKeyMaterial() throws {
		var schedule = NoiseKeySchedule()

		try schedule.mixIntoKey(Data(hexString: "00112233445566778899aabbccddeeff"))

		#expect(schedule.salt.hexString == "19a9195895d761fb60277919ca60860fabe678eb30e00c654f669b74fdb8325e")
		#expect(schedule.encryptionKey.hexString == "bfa88a2f6cd16f393c501b81421a14ff12d2201a0f5f4db9f8e31b22ad08ae47")
		#expect(schedule.decryptionKey == schedule.encryptionKey)
	}

	@Test("derives transport keys from empty input after key mixing")
	func derivesTransportKeys() throws {
		var schedule = NoiseKeySchedule()
		try schedule.mixIntoKey(Data(hexString: "00112233445566778899aabbccddeeff"))

		let keys = try schedule.deriveTransportKeys()

		#expect(keys.write.hexString == "b5af4a6ec38bc5d5fda964738ac4ee5910073db2a44244d951e1ff0b57532074")
		#expect(keys.read.hexString == "2eba366fccb1a15881aaa11a3c53e063119ad4508f5ca82a3019487b7538c588")
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw NoiseKeyScheduleTestError.invalidHex
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

private enum NoiseKeyScheduleTestError: Error {
	case invalidHex
}
