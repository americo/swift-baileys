import CryptoKit
import Foundation

public struct LinkCodeCompanionRegistrationResult: Sendable {
	public var reply: BinaryNode
	public var advSecretKey: String
}

public protocol LinkCodeCompanionRegistrationProcessing: Sendable {
	func processLinkCodeCompanionRegistration(
		stanza: BinaryNode,
		credentials: AuthenticationCredentials,
		requestID: String
	) throws -> LinkCodeCompanionRegistrationResult
}

public struct DefaultLinkCodeCompanionRegistrationProcessor: LinkCodeCompanionRegistrationProcessing {
	private let randomBytes: @Sendable (Int) throws -> Data

	public init(randomBytes: @escaping @Sendable (Int) throws -> Data = MessageIDGenerator.secureRandomBytes(count:)) {
		self.randomBytes = randomBytes
	}

	public func processLinkCodeCompanionRegistration(
		stanza: BinaryNode,
		credentials: AuthenticationCredentials,
		requestID: String
	) throws -> LinkCodeCompanionRegistrationResult {
		guard let registration = stanza.firstChild(named: "link_code_companion_reg") else {
			throw LinkCodeCompanionRegistrationError.missingRegistrationNode
		}

		guard let meID = credentials.me?.id else {
			throw LinkCodeCompanionRegistrationError.missingAuthenticatedUser
		}

		guard let pairingCode = credentials.pairingCode else {
			throw LinkCodeCompanionRegistrationError.missingPairingCode
		}

		guard let pairingReference = registration.childData(named: "link_code_pairing_ref"),
			  let primaryIdentityPublicKey = registration.childData(named: "primary_identity_pub"),
			  let wrappedPrimaryEphemeralPublicKey = registration
			  	.childData(named: "link_code_pairing_wrapped_primary_ephemeral_pub") else {
			throw LinkCodeCompanionRegistrationError.missingPairingFields
		}

		let primaryEphemeralPublicKey = try PairingCode.unwrapPrimaryEphemeralPublicKey(
			wrappedPrimaryEphemeralPublicKey,
			pairingCode: pairingCode
		)
		let companionSharedKey = try NoiseCurve25519.sharedSecret(
			privateKey: credentials.pairingEphemeralKeyPair.privateKey,
			publicKey: primaryEphemeralPublicKey
		)
		let random = try randomData(count: 32)
		let bundleSalt = try randomData(count: 32)
		let bundleIV = try randomData(count: 12)
		let bundleKey = Self.hkdf(
			input: companionSharedKey,
			salt: bundleSalt,
			info: "link_code_pairing_key_bundle_encryption_key",
			outputByteCount: 32
		)
		let bundlePlaintext = credentials.signedIdentityKey.publicKey + primaryIdentityPublicKey + random
		let encryptedBundle = try Self.aesGCMEncrypt(bundlePlaintext, key: bundleKey, iv: bundleIV)
		let identitySharedKey = try NoiseCurve25519.sharedSecret(
			privateKey: credentials.signedIdentityKey.privateKey,
			publicKey: primaryIdentityPublicKey
		)
		let advSecretKey = Self.hkdf(
			input: companionSharedKey + identitySharedKey + random,
			salt: Data(),
			info: "adv_secret",
			outputByteCount: 32
		).base64EncodedString()

		return LinkCodeCompanionRegistrationResult(
			reply: BinaryNode(
				tag: "iq",
				attrs: ["to": "@s.whatsapp.net", "type": "set", "id": requestID, "xmlns": "md"],
				content: .nodes([
					BinaryNode(
						tag: "link_code_companion_reg",
						attrs: ["jid": meID, "stage": "companion_finish"],
						content: .nodes([
							BinaryNode(
								tag: "link_code_pairing_wrapped_key_bundle",
								content: .data(bundleSalt + bundleIV + encryptedBundle)
							),
							BinaryNode(
								tag: "companion_identity_public",
								content: .data(credentials.signedIdentityKey.publicKey)
							),
							BinaryNode(tag: "link_code_pairing_ref", content: .data(pairingReference))
						])
					)
				])
			),
			advSecretKey: advSecretKey
		)
	}

	private func randomData(count: Int) throws -> Data {
		let data = try randomBytes(count)
		guard data.count == count else {
			throw LinkCodeCompanionRegistrationError.invalidRandomByteCount
		}

		return data
	}

	private static func hkdf(input: Data, salt: Data, info: String, outputByteCount: Int) -> Data {
		let key = HKDF<SHA256>.deriveKey(
			inputKeyMaterial: SymmetricKey(data: input),
			salt: salt,
			info: Data(info.utf8),
			outputByteCount: outputByteCount
		)
		return key.withUnsafeBytes { Data($0) }
	}

	private static func aesGCMEncrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
		let nonce = try AES.GCM.Nonce(data: iv)
		let box = try AES.GCM.seal(data, using: SymmetricKey(data: key), nonce: nonce)
		return box.ciphertext + box.tag
	}
}

public enum LinkCodeCompanionRegistrationError: Error, Equatable, Sendable {
	case missingRegistrationNode
	case missingAuthenticatedUser
	case missingPairingCode
	case missingPairingFields
	case invalidRandomByteCount
}
