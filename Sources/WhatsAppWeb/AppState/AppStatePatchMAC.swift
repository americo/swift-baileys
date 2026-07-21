import CryptoKit
import Foundation

enum AppStatePatchMAC {
	static func indexMac(index: Data, key: Data) -> Data {
		HMAC<SHA256>.authenticationCode(for: index, using: SymmetricKey(data: key)).data
	}

	static func valueMac(operation: ChatModificationPatchOperation, encryptedValue: Data, keyID: Data, key: Data) -> Data {
		let operationByte: UInt8 = operation == .set ? 0x01 : 0x02
		let keyData = Data([operationByte]) + keyID
		var trailer = Data(repeating: 0, count: 8)
		trailer[7] = UInt8(keyData.count)
		let code = HMAC<SHA512>.authenticationCode(
			for: keyData + encryptedValue + trailer,
			using: SymmetricKey(data: key)
		)
		return Data(code).prefixData(32)
	}

	static func snapshotMac(hash: Data, version: UInt64, patchType: ChatModificationPatchType, key: Data) -> Data {
		HMAC<SHA256>.authenticationCode(
			for: hash + networkOrder(version) + Data(patchType.rawValue.utf8),
			using: SymmetricKey(data: key)
		).data
	}

	static func patchMac(snapshotMac: Data, valueMacs: [Data], version: UInt64, patchType: ChatModificationPatchType, key: Data) -> Data {
		let payload = valueMacs.reduce(snapshotMac) { $0 + $1 } + networkOrder(version) + Data(patchType.rawValue.utf8)
		return HMAC<SHA256>.authenticationCode(for: payload, using: SymmetricKey(data: key)).data
	}

	private static func networkOrder(_ value: UInt64) -> Data {
		withUnsafeBytes(of: value.bigEndian) { Data($0) }
	}
}

private extension HashedAuthenticationCode {
	var data: Data {
		Data(self)
	}
}

private extension Data {
	func prefixData(_ count: Int) -> Data {
		Data(prefix(count))
	}
}
