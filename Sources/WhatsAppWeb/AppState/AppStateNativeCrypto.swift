import CryptoKit
import Foundation

public struct NativeAppStateKeyExpander: AppStateKeyExpanding {
	public init() {}

	public func expand(keyData: Data) throws -> AppStatePatchKeySet {
		let expanded = HKDF<SHA256>.deriveKey(
			inputKeyMaterial: SymmetricKey(data: keyData),
			salt: Data(),
			info: Data("WhatsApp Mutation Keys".utf8),
			outputByteCount: 160
		).data
		return AppStatePatchKeySet(
			indexKey: expanded[range: 0..<32],
			valueEncryptionKey: expanded[range: 32..<64],
			valueMacKey: expanded[range: 64..<96],
			snapshotMacKey: expanded[range: 96..<128],
			patchMacKey: expanded[range: 128..<160]
		)
	}
}

public struct NativeAppStatePatchHashMixer: AppStatePatchHashMixing {
	public init() {}

	public func subtractThenAdd(hash: Data, subtract: [Data], add: [Data]) throws -> Data {
		guard hash.count == 128 else {
			throw NativeAppStatePatchHashMixerError.invalidHashLength
		}

		var result = hash
		for value in subtract {
			try mix(value, into: &result, subtracting: true)
		}
		for value in add {
			try mix(value, into: &result, subtracting: false)
		}
		return result
	}

	private func mix(_ value: Data, into result: inout Data, subtracting: Bool) throws {
		let expanded = HKDF<SHA256>.deriveKey(
			inputKeyMaterial: SymmetricKey(data: value),
			salt: Data(),
			info: Data("WhatsApp Patch Integrity".utf8),
			outputByteCount: 128
		).data
		guard expanded.count == result.count, expanded.count.isMultiple(of: 2) else {
			throw NativeAppStatePatchHashMixerError.invalidExpandedValueLength
		}

		for offset in stride(from: 0, to: result.count, by: 2) {
			let current = UInt16(result[offset]) | (UInt16(result[offset + 1]) << 8)
			let delta = UInt16(expanded[offset]) | (UInt16(expanded[offset + 1]) << 8)
			let mixed = subtracting ? current &- delta : current &+ delta
			result[offset] = UInt8(mixed & 0xff)
			result[offset + 1] = UInt8(mixed >> 8)
		}
	}
}

public enum NativeAppStatePatchHashMixerError: Error, Equatable, Sendable {
	case invalidHashLength
	case invalidExpandedValueLength
}

private extension SymmetricKey {
	var data: Data {
		withUnsafeBytes { Data($0) }
	}
}

private extension Data {
	subscript(range range: Range<Int>) -> Data {
		Data(self[index(startIndex, offsetBy: range.lowerBound)..<index(startIndex, offsetBy: range.upperBound)])
	}
}
