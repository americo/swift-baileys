import Foundation

public struct SignalPreKey: Equatable, Sendable {
	public let keyID: Int
	public let publicKey: Data
	public let signature: Data?

	public var curve25519PublicKey: Data? {
		Self.curve25519PublicKey(from: publicKey)
	}

	public init(keyID: Int, publicKey: Data, signature: Data? = nil) {
		self.keyID = keyID
		self.publicKey = publicKey
		self.signature = signature
	}

	public static func curve25519PublicKey(from signalPublicKey: Data) -> Data? {
		SignalPublicKey.curve25519PublicKey(from: signalPublicKey)
	}
}

public struct SignalSessionBundle: Equatable, Sendable {
	public let jid: String
	public let registrationID: Int
	public let identityKey: Data
	public let signedPreKey: SignalPreKey
	public let preKey: SignalPreKey

	public var address: SignalProtocolAddress? {
		SignalProtocolAddress(jid: jid)
	}

	public var identityCurve25519PublicKey: Data? {
		SignalPreKey.curve25519PublicKey(from: identityKey)
	}

	public var hasValidSignalKeyMaterial: Bool {
		SignalPreKey.curve25519PublicKey(from: identityKey) != nil
			&& signedPreKey.curve25519PublicKey != nil
			&& signedPreKey.signature?.count == 64
			&& preKey.curve25519PublicKey != nil
	}

	public func validatedAddress() throws -> SignalProtocolAddress {
		let address: SignalProtocolAddress
		do {
			address = try SignalProtocolAddress.validated(jid: jid)
		} catch {
			throw SignalSessionBundleValidationError.invalidAddress
		}
		guard hasValidSignalKeyMaterial else {
			throw SignalSessionBundleValidationError.invalidKeyMaterial
		}

		return address
	}

	public func nativeInstallRequest(localJID: String? = nil) throws -> SignalSessionNativeInstallRequest {
		let address = try validatedAddress()
		let localAddress: SignalProtocolAddress?
		if let localJID {
			localAddress = try SignalProtocolAddress.validated(jid: localJID)
		} else {
			localAddress = nil
		}
		guard let identityKey = identityCurve25519PublicKey,
			  let signedPreKeyPublicKey = signedPreKey.curve25519PublicKey,
			  let signedPreKeySignature = signedPreKey.signature,
			  signedPreKeySignature.count == 64,
			  let preKeyPublicKey = preKey.curve25519PublicKey else {
			throw SignalSessionBundleValidationError.invalidKeyMaterial
		}
		guard (1...0xFF_FF_FF).contains(signedPreKey.keyID),
			  (1...0xFF_FF_FF).contains(preKey.keyID) else {
			throw SignalSessionBundleValidationError.invalidKeyID
		}

		return SignalSessionNativeInstallRequest(
			jid: jid,
			address: address,
			localJID: localJID,
			localAddress: localAddress,
			registrationID: registrationID,
			identityCurve25519PublicKey: identityKey,
			signedPreKeyID: signedPreKey.keyID,
			signedPreKeyCurve25519PublicKey: signedPreKeyPublicKey,
			signedPreKeySignature: signedPreKeySignature,
			preKeyID: preKey.keyID,
			preKeyCurve25519PublicKey: preKeyPublicKey
		)
	}

	public init(
		jid: String,
		registrationID: Int,
		identityKey: Data,
		signedPreKey: SignalPreKey,
		preKey: SignalPreKey
	) {
		self.jid = jid
		self.registrationID = registrationID
		self.identityKey = identityKey
		self.signedPreKey = signedPreKey
		self.preKey = preKey
	}

}

public struct SignalSessionNativeInstallRequest: Equatable, Sendable {
	public let jid: String
	public let address: SignalProtocolAddress
	public let localJID: String?
	public let localAddress: SignalProtocolAddress?
	public let registrationID: Int
	public let identityCurve25519PublicKey: Data
	public let signedPreKeyID: Int
	public let signedPreKeyCurve25519PublicKey: Data
	public let signedPreKeySignature: Data
	public let preKeyID: Int
	public let preKeyCurve25519PublicKey: Data

	public init(
		jid: String,
		address: SignalProtocolAddress,
		localJID: String? = nil,
		localAddress: SignalProtocolAddress? = nil,
		registrationID: Int,
		identityCurve25519PublicKey: Data,
		signedPreKeyID: Int,
		signedPreKeyCurve25519PublicKey: Data,
		signedPreKeySignature: Data,
		preKeyID: Int,
		preKeyCurve25519PublicKey: Data
	) {
		self.jid = jid
		self.address = address
		self.localJID = localJID
		self.localAddress = localAddress
		self.registrationID = registrationID
		self.identityCurve25519PublicKey = identityCurve25519PublicKey
		self.signedPreKeyID = signedPreKeyID
		self.signedPreKeyCurve25519PublicKey = signedPreKeyCurve25519PublicKey
		self.signedPreKeySignature = signedPreKeySignature
		self.preKeyID = preKeyID
		self.preKeyCurve25519PublicKey = preKeyCurve25519PublicKey
	}

	public func validate() throws {
		guard SignalProtocolAddress(jid: jid) == address else {
			throw SignalSessionBundleValidationError.invalidAddress
		}
		if let localJID {
			guard SignalProtocolAddress(jid: localJID) == localAddress else {
				throw SignalSessionBundleValidationError.invalidAddress
			}
		} else if localAddress != nil {
			throw SignalSessionBundleValidationError.invalidAddress
		}
		guard identityCurve25519PublicKey.count == 32,
			  signedPreKeyCurve25519PublicKey.count == 32,
			  signedPreKeySignature.count == 64,
			  preKeyCurve25519PublicKey.count == 32 else {
			throw SignalSessionBundleValidationError.invalidKeyMaterial
		}
		guard (1...0xFF_FF_FF).contains(signedPreKeyID),
			  (1...0xFF_FF_FF).contains(preKeyID) else {
			throw SignalSessionBundleValidationError.invalidKeyID
		}
	}
}

public enum SignalSessionBundleValidationError: Error, Equatable, Sendable {
	case invalidAddress
	case invalidKeyID
	case invalidKeyMaterial
}

public struct SignalSessionBundleResolver: Sendable {
	public typealias Query = @Sendable (_ node: BinaryNode, _ timeout: Duration) async throws -> BinaryNode

	private let query: Query
	private let idGenerator: @Sendable () -> String

	public init(query: @escaping Query, idGenerator: @escaping @Sendable () -> String = { UUID().uuidString }) {
		self.query = query
		self.idGenerator = idGenerator
	}

	public func fetchBundles(for jids: [String], force: Bool = false) async throws -> [SignalSessionBundle] {
		let response = try await query(try Self.makeRequest(for: jids, id: idGenerator(), force: force), .seconds(60))
		return try Self.parseBundles(from: response)
	}

	public static func makeRequest(for jids: [String], id: String, force: Bool = false) throws -> BinaryNode {
		guard !id.isEmpty else {
			throw SignalSessionBundleResolverError.emptyRequestID
		}
		guard !jids.isEmpty else {
			throw SignalSessionBundleResolverError.emptyJIDs
		}
		for jid in jids where SignalProtocolAddress(jid: jid) == nil {
			throw SignalSessionBundleResolverError.invalidJID(jid)
		}

		return BinaryNode(
			tag: "iq",
			attrs: ["id": id, "xmlns": "encrypt", "type": "get", "to": "@s.whatsapp.net"],
			content: .nodes([
				BinaryNode(
					tag: "key",
					content: .nodes(
						jids.map { jid in
							var attrs: BinaryNode.Attributes = ["jid": jid]
							if force {
								attrs = BinaryNode.Attributes([("jid", jid), ("reason", "identity")])
							}

							return BinaryNode(tag: "user", attrs: attrs)
						}
					)
				)
			])
		)
	}

	public static func parseBundles(from response: BinaryNode) throws -> [SignalSessionBundle] {
		var bundles: [SignalSessionBundle] = []
		for user in response.firstChild(named: "list")?.children(named: "user") ?? [] {
			guard let jid = user.attrs["jid"],
				  SignalProtocolAddress(jid: jid) != nil,
				  let registrationID = user.unsignedIntegerChild(named: "registration", length: 4),
				  let identity = user.childData(named: "identity"),
				  let signedPreKeyNode = user.firstChild(named: "skey"),
				  let preKeyNode = user.firstChild(named: "key") else {
				throw SignalSessionBundleResolverError.invalidBundle
			}

			bundles.append(
				SignalSessionBundle(
					jid: jid,
					registrationID: registrationID,
					identityKey: try signalPublicKey(identity),
					signedPreKey: try parsePreKey(signedPreKeyNode, requiresSignature: true),
					preKey: try parsePreKey(preKeyNode, requiresSignature: false)
				)
			)
		}

		return bundles
	}

	private static func parsePreKey(_ node: BinaryNode, requiresSignature: Bool) throws -> SignalPreKey {
		guard let keyID = node.unsignedIntegerChild(named: "id", length: 3),
			  let value = node.childData(named: "value") else {
			throw SignalSessionBundleResolverError.invalidBundle
		}

		let signature = node.childData(named: "signature")
		if requiresSignature && signature == nil {
			throw SignalSessionBundleResolverError.invalidBundle
		}
		if requiresSignature && signature?.count != 64 {
			throw SignalSessionBundleResolverError.invalidBundle
		}

		return SignalPreKey(keyID: keyID, publicKey: try signalPublicKey(value), signature: signature)
	}

	private static func signalPublicKey(_ value: Data) throws -> Data {
		do {
			let formatted = try SignalPublicKey.format(value)
			guard formatted.first == SignalPublicKey.keyBundleType.first else {
				throw SignalSessionBundleResolverError.invalidBundle
			}

			return formatted
		} catch SignalPublicKeyError.invalidKeyMaterial {
			throw SignalSessionBundleResolverError.invalidBundle
		}
	}
}

public enum SignalSessionBundleResolverError: Error, Equatable, Sendable {
	case emptyRequestID
	case emptyJIDs
	case invalidJID(String)
	case invalidBundle
}
