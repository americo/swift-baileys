import Foundation

public enum SignalPublicKey {
	public static let keyBundleType = Data([0x05])

	public static func format(_ publicKey: Data) throws -> Data {
		switch publicKey.count {
		case 32:
			return keyBundleType + publicKey
		case 33:
			return publicKey
		default:
			throw SignalPublicKeyError.invalidKeyMaterial
		}
	}

	public static func curve25519PublicKey(from publicKey: Data) -> Data? {
		guard publicKey.count == 33, publicKey.first == keyBundleType.first else {
			return nil
		}

		return publicKey.dropFirst()
	}
}

public enum SignalPublicKeyError: Error, Equatable, Sendable {
	case invalidKeyMaterial
}
