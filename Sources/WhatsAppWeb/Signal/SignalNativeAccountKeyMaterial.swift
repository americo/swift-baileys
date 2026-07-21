import Foundation

public struct SignalNativeAccountKeyMaterial: Equatable, Sendable {
	public let registrationID: Int
	public let identityPrivateKey: Data
	public let identityCurve25519PublicKey: Data
	public let signedPreKeyID: Int
	public let signedPreKeyPrivateKey: Data
	public let signedPreKeyCurve25519PublicKey: Data
	public let signedPreKeySignature: Data

	public init(
		registrationID: Int,
		identityPrivateKey: Data,
		identityCurve25519PublicKey: Data,
		signedPreKeyID: Int,
		signedPreKeyPrivateKey: Data,
		signedPreKeyCurve25519PublicKey: Data,
		signedPreKeySignature: Data
	) {
		self.registrationID = registrationID
		self.identityPrivateKey = identityPrivateKey
		self.identityCurve25519PublicKey = identityCurve25519PublicKey
		self.signedPreKeyID = signedPreKeyID
		self.signedPreKeyPrivateKey = signedPreKeyPrivateKey
		self.signedPreKeyCurve25519PublicKey = signedPreKeyCurve25519PublicKey
		self.signedPreKeySignature = signedPreKeySignature
	}

	public func validate() throws {
		guard identityCurve25519PublicKey.count == 32,
			  signedPreKeyCurve25519PublicKey.count == 32,
			  signedPreKeySignature.count == 64 else {
			throw SignalNativeKeyMaterialError.invalidKeyMaterial
		}
		guard (1...0xFF_FF_FF).contains(signedPreKeyID) else {
			throw SignalNativeKeyMaterialError.invalidKeyID
		}
	}
}

public struct SignalNativeAccountImportRequest: Equatable, Sendable {
	public let localJID: String
	public let localAddress: SignalProtocolAddress
	public let keyMaterial: SignalNativeAccountKeyMaterial

	public init(
		localJID: String,
		localAddress: SignalProtocolAddress,
		keyMaterial: SignalNativeAccountKeyMaterial
	) {
		self.localJID = localJID
		self.localAddress = localAddress
		self.keyMaterial = keyMaterial
	}

	public func validate() throws {
		guard SignalProtocolAddress(jid: localJID) == localAddress else {
			throw SignalNativeKeyMaterialError.invalidLocalJID
		}
		try keyMaterial.validate()
	}
}

public protocol SignalNativeAccountImporting: Sendable {
	func importAccount(_ request: SignalNativeAccountImportRequest) async throws
}

public protocol SignalNativeAccountImportChecking: Sendable {
	func containsAccount(_ request: SignalNativeAccountImportRequest) async throws -> Bool
}

public struct SignalNativeAccountImportResult: Equatable, Sendable {
	public let request: SignalNativeAccountImportRequest
	public let imported: Bool

	public init(request: SignalNativeAccountImportRequest, imported: Bool) {
		self.request = request
		self.imported = imported
	}
}

public extension SignalNativeAccountImporting {
	func importAccount(credentials: AuthenticationCredentials) async throws {
		try await importAccount(credentials.nativeAccountImportRequest())
	}
}

public extension AuthenticationCredentials {
	func nativeAccountKeyMaterial() throws -> SignalNativeAccountKeyMaterial {
		guard let identityKey = Self.nativeCurve25519PublicKey(from: signedIdentityKey.publicKey),
			  let signedPreKeyPublicKey = Self.nativeCurve25519PublicKey(from: signedPreKey.keyPair.publicKey),
			  signedPreKey.signature.count == 64 else {
			throw SignalNativeKeyMaterialError.invalidKeyMaterial
		}
		guard (1...0xFF_FF_FF).contains(signedPreKey.keyID) else {
			throw SignalNativeKeyMaterialError.invalidKeyID
		}

		return SignalNativeAccountKeyMaterial(
			registrationID: registrationID,
			identityPrivateKey: signedIdentityKey.privateKey,
			identityCurve25519PublicKey: identityKey,
			signedPreKeyID: signedPreKey.keyID,
			signedPreKeyPrivateKey: signedPreKey.keyPair.privateKey,
			signedPreKeyCurve25519PublicKey: signedPreKeyPublicKey,
			signedPreKeySignature: signedPreKey.signature
		)
	}

	func nativeAccountImportRequest() throws -> SignalNativeAccountImportRequest {
		guard let localJID = me?.id else {
			throw SignalNativeKeyMaterialError.missingLocalUser
		}
		guard let localAddress = SignalProtocolAddress(jid: localJID) else {
			throw SignalNativeKeyMaterialError.invalidLocalJID
		}

		return SignalNativeAccountImportRequest(
			localJID: localJID,
			localAddress: localAddress,
			keyMaterial: try nativeAccountKeyMaterial()
		)
	}

	private static func nativeCurve25519PublicKey(from publicKey: Data) -> Data? {
		if publicKey.count == 32 {
			return publicKey
		}

		return SignalPreKey.curve25519PublicKey(from: publicKey)
	}
}

public enum SignalNativeKeyMaterialError: Error, Equatable, Sendable {
	case invalidKeyID
	case invalidKeyMaterial
	case invalidLocalJID
	case missingLocalUser
}
