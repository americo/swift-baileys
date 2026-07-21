import CryptoKit
import Foundation
import Security

public struct AuthenticationCredentialsFactory: Sendable {
	public typealias KeyPairGenerator = @Sendable () throws -> AuthenticationKeyPair
	public typealias RandomBytesGenerator = @Sendable (Int) throws -> Data
	public typealias Signer = @Sendable (_ privateKey: Data, _ payload: Data) throws -> Data
	private typealias SignedPreKeySigner = @Sendable (_ request: SignalSignedPreKeySignatureRequest) throws -> Data

	private let keyPairGenerator: KeyPairGenerator
	private let randomBytes: RandomBytesGenerator
	private let signer: SignedPreKeySigner

	public init(
		keyPairGenerator: @escaping KeyPairGenerator = Self.makeCurve25519KeyPair,
		randomBytes: @escaping RandomBytesGenerator = Self.secureRandomBytes(count:),
		signer: @escaping Signer
	) {
		self.keyPairGenerator = keyPairGenerator
		self.randomBytes = randomBytes
		self.signer = { request in
			try signer(request.identityPrivateKey, request.payload)
		}
	}

	public init(
		keyPairGenerator: @escaping KeyPairGenerator = Self.makeCurve25519KeyPair,
		randomBytes: @escaping RandomBytesGenerator = Self.secureRandomBytes(count:),
		signedPreKeySigner: any SignalSignedPreKeySigning
	) {
		self.keyPairGenerator = keyPairGenerator
		self.randomBytes = randomBytes
		self.signer = { request in
			try signedPreKeySigner.signSignedPreKey(request)
		}
	}

	public init(
		nativeSignalAdapter: any WhatsAppNativeSignalAdapter,
		keyPairGenerator: @escaping KeyPairGenerator = Self.makeCurve25519KeyPair,
		randomBytes: @escaping RandomBytesGenerator = Self.secureRandomBytes(count:)
	) {
		self.init(
			keyPairGenerator: keyPairGenerator,
			randomBytes: randomBytes,
			signedPreKeySigner: nativeSignalAdapter
		)
	}

	public func makeCredentials() throws -> AuthenticationCredentials {
		let identityKey = try keyPairGenerator()
		guard identityKey.privateKey.count == 32, identityKey.publicKey.count == 32 else {
			throw AuthenticationCredentialsFactoryError.invalidKeyPairMaterial
		}
		let noiseKey = try keyPairGenerator()
		guard noiseKey.privateKey.count == 32, noiseKey.publicKey.count == 32 else {
			throw AuthenticationCredentialsFactoryError.invalidKeyPairMaterial
		}
		let pairingEphemeralKeyPair = try keyPairGenerator()
		guard pairingEphemeralKeyPair.privateKey.count == 32, pairingEphemeralKeyPair.publicKey.count == 32 else {
			throw AuthenticationCredentialsFactoryError.invalidKeyPairMaterial
		}
		let signedPreKey = try makeSignedPreKey(identityKey: identityKey, keyID: 1)
		let advSecretKey = try randomBytes(32)
		guard advSecretKey.count == 32 else {
			throw AuthenticationCredentialsFactoryError.invalidRandomByteCount
		}

		return AuthenticationCredentials(
			noiseKey: noiseKey,
			pairingEphemeralKeyPair: pairingEphemeralKeyPair,
			signedIdentityKey: identityKey,
			signedPreKey: signedPreKey,
			registrationID: try makeRegistrationID(),
			advSecretKey: advSecretKey.base64EncodedString(),
			nextPreKeyID: 1,
			firstUnuploadedPreKeyID: 1,
			accountSyncCounter: 0,
			registered: false
		)
	}

	public static func makeCurve25519KeyPair() throws -> AuthenticationKeyPair {
		let privateKey = Curve25519.KeyAgreement.PrivateKey()
		return AuthenticationKeyPair(
			privateKey: privateKey.rawRepresentation,
			publicKey: privateKey.publicKey.rawRepresentation
		)
	}

	public static func secureRandomBytes(count: Int) throws -> Data {
		var bytes = [UInt8](repeating: 0, count: count)
		let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)

		guard status == errSecSuccess else {
			throw AuthenticationCredentialsFactoryError.randomBytesFailed(status)
		}

		return Data(bytes)
	}

	private func makeSignedPreKey(identityKey: AuthenticationKeyPair, keyID: Int) throws -> SignedAuthenticationKeyPair {
		do {
			return try SignalSignedKeyPairFactory.make(
				identityKeyPair: identityKey,
				keyID: keyID,
				keyPairGenerator: keyPairGenerator,
				signer: signer
			)
		} catch SignalSignedKeyPairFactoryError.invalidKeyPairMaterial {
			throw AuthenticationCredentialsFactoryError.invalidKeyPairMaterial
		} catch SignalSignedKeyPairFactoryError.invalidSignature {
			throw AuthenticationCredentialsFactoryError.invalidSignedPreKeySignature
		} catch {
			throw error
		}
	}

	private func makeRegistrationID() throws -> Int {
		do {
			return try RegistrationIDGenerator.generate(randomBytes: randomBytes)
		} catch RegistrationIDGeneratorError.invalidRandomByteCount {
			throw AuthenticationCredentialsFactoryError.invalidRandomByteCount
		} catch {
			throw error
		}
	}
}

public enum AuthenticationCredentialsFactoryError: Error, Equatable, Sendable {
	case invalidKeyPairMaterial
	case invalidRandomByteCount
	case invalidSignedPreKeySignature
	case randomBytesFailed(OSStatus)
}

public struct SignalSignedPreKeySignatureRequest: Equatable, Sendable {
	public let identityPrivateKey: Data
	public let signedPreKeyPublicKey: Data
	public let payload: Data

	public init(identityPrivateKey: Data, signedPreKeyPublicKey: Data) {
		self.identityPrivateKey = identityPrivateKey
		self.signedPreKeyPublicKey = signedPreKeyPublicKey
		self.payload = (try? SignalPublicKey.format(signedPreKeyPublicKey)) ?? signedPreKeyPublicKey
	}
}

public protocol SignalSignedPreKeySigning: Sendable {
	func signSignedPreKey(_ request: SignalSignedPreKeySignatureRequest) throws -> Data
}

public enum SignalSignedPreKeySigningError: Error, Equatable, Sendable {
	case invalidSignedPreKeySignature
}

public extension SignalSignedPreKeySigning {
	func assertReadyForCredentialSigning() throws {
		let identityKey = try AuthenticationCredentialsFactory.makeCurve25519KeyPair()
		let signedPreKey = try AuthenticationCredentialsFactory.makeCurve25519KeyPair()
		let signature = try signSignedPreKey(SignalSignedPreKeySignatureRequest(
			identityPrivateKey: identityKey.privateKey,
			signedPreKeyPublicKey: signedPreKey.publicKey
		))
		guard signature.count == 64 else {
			throw SignalSignedPreKeySigningError.invalidSignedPreKeySignature
		}
	}
}
