import CryptoKit
import Foundation

public enum NoiseCurve25519Error: Error {
	case invalidPrivateKey
	case invalidPublicKey
}

public enum NoiseCurve25519 {
	public static func publicKey(privateKey: Data) throws -> Data {
		let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
		return privateKey.publicKey.rawRepresentation
	}

	public static func sharedSecret(privateKey: Data, publicKey: Data) throws -> Data {
		let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
		let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)
		let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
		return sharedSecret.withUnsafeBytes { Data($0) }
	}
}
