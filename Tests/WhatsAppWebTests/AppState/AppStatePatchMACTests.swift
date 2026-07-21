import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("App-state patch MAC")
struct AppStatePatchMACTests {
	@Test("builds value MACs matching Baileys operation framing")
	func buildsValueMACsMatchingBaileysOperationFraming() throws {
		let keyID = Data([1, 2, 3, 4, 5, 6, 7, 8])
		let encryptedValue = try Data(hexString: "00112233445566778899aabbccddeeff")
		let key = try Data(hexString: "101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f")

		#expect(AppStatePatchMAC.valueMac(
			operation: .set,
			encryptedValue: encryptedValue,
			keyID: keyID,
			key: key
		) == (try Data(hexString: "8cbcf8b2089616dd028cbec4aca0da51b8a32c9c2cafeb010486a8278c6aceb4")))
		#expect(AppStatePatchMAC.valueMac(
			operation: .remove,
			encryptedValue: encryptedValue,
			keyID: keyID,
			key: key
		) == (try Data(hexString: "a207e1257696cc81a7a5e03af4f8c8c9a37be6abed91644a1d222ba2191afc4b")))
	}

	@Test("builds snapshot and patch MACs matching Baileys framing")
	func buildsSnapshotAndPatchMACsMatchingBaileysFraming() throws {
		let hash = Data((0..<128).map(UInt8.init))
		let snapshotKey = try Data(hexString: "303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f")
		let patchKey = try Data(hexString: "505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f")
		let valueMac = try Data(hexString: "8cbcf8b2089616dd028cbec4aca0da51b8a32c9c2cafeb010486a8278c6aceb4")

		let snapshotMac = AppStatePatchMAC.snapshotMac(
			hash: hash,
			version: 7,
			patchType: .regularHigh,
			key: snapshotKey
		)

		#expect(snapshotMac == (try Data(hexString: "7359a18a54daa038fe9e372dc59ef0ccb191020893f849a3fae530286c5d225c")))
		#expect(AppStatePatchMAC.patchMac(
			snapshotMac: snapshotMac,
			valueMacs: [valueMac],
			version: 7,
			patchType: .regularHigh,
			key: patchKey
		) == (try Data(hexString: "57d477de562146dbb83a720fcd90aaf54ca1a822ab646b6b8fc1de2b32a6c5e2")))
	}
}

private extension Data {
	init(hexString: String) throws {
		guard hexString.count.isMultiple(of: 2) else {
			throw HexDataError.invalidLength
		}

		var bytes = [UInt8]()
		bytes.reserveCapacity(hexString.count / 2)
		var index = hexString.startIndex
		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw HexDataError.invalidByte
			}
			bytes.append(byte)
			index = next
		}
		self = Data(bytes)
	}
}

private enum HexDataError: Error {
	case invalidLength
	case invalidByte
}
