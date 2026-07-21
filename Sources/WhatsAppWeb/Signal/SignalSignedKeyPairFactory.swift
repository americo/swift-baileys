import Foundation

public enum SignalSignedKeyPairFactory {
	public typealias KeyPairGenerator = @Sendable () throws -> AuthenticationKeyPair
	public typealias SignatureGenerator = @Sendable (_ request: SignalSignedPreKeySignatureRequest) throws -> Data

	public static func make(
		identityKeyPair: AuthenticationKeyPair,
		keyID: Int,
		keyPairGenerator: KeyPairGenerator = AuthenticationCredentialsFactory.makeCurve25519KeyPair,
		signer: SignatureGenerator
	) throws -> SignedAuthenticationKeyPair {
		guard identityKeyPair.privateKey.count == 32, identityKeyPair.publicKey.count == 32 else {
			throw SignalSignedKeyPairFactoryError.invalidKeyPairMaterial
		}

		let keyPair = try keyPairGenerator()
		guard keyPair.privateKey.count == 32, keyPair.publicKey.count == 32 else {
			throw SignalSignedKeyPairFactoryError.invalidKeyPairMaterial
		}

		let signature = try signer(SignalSignedPreKeySignatureRequest(
			identityPrivateKey: identityKeyPair.privateKey,
			signedPreKeyPublicKey: keyPair.publicKey
		))
		guard signature.count == 64 else {
			throw SignalSignedKeyPairFactoryError.invalidSignature
		}

		return SignedAuthenticationKeyPair(
			keyPair: keyPair,
			signature: signature,
			keyID: keyID
		)
	}
}

public enum SignalSignedKeyPairFactoryError: Error, Equatable, Sendable {
	case invalidKeyPairMaterial
	case invalidSignature
}
