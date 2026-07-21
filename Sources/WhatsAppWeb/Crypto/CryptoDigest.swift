import CryptoKit
import Foundation

public enum CryptoDigest {
	public enum HMACVariant: Sendable {
		case sha256
		case sha512
	}

	public static func hmacSign(_ data: Data, key: Data, variant: HMACVariant = .sha256) -> Data {
		switch variant {
		case .sha256:
			return Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
		case .sha512:
			return Data(HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: key)))
		}
	}

	public static func sha256(_ data: Data) -> Data {
		Data(SHA256.hash(data: data))
	}
}
