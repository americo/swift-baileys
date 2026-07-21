import Foundation

struct StoredPreKey: Codable, Equatable, Sendable {
	let privateKey: Data
	let publicKey: Data
}

struct PreKeyUploadRequest: Sendable {
	let node: BinaryNode
	let preKeys: [String: StoredPreKey]
	let nextPreKeyID: Int
	let firstUnuploadedPreKeyID: Int
}

enum PreKeyUploadRequestError: Error, Equatable, Sendable {
	case invalidKeyID
	case invalidKeyMaterial
	case invalidRequestedUploadCount
}

public struct SignalNativePreKeyUploadRequest: Equatable, Sendable {
	public let localJID: String?
	public let localAddress: SignalProtocolAddress?
	public let currentServerPreKeyCount: Int?
	public let registrationID: Int
	public let identityPrivateKey: Data
	public let identityCurve25519PublicKey: Data
	public let signedPreKeyID: Int
	public let signedPreKeyPrivateKey: Data
	public let signedPreKeyCurve25519PublicKey: Data
	public let signedPreKeySignature: Data
	public let firstUnuploadedPreKeyID: Int
	public let requestedUploadCount: Int

	public var preKeyIDs: [Int] {
		guard requestedUploadCount > 0 else { return [] }
		return Array(firstUnuploadedPreKeyID..<nextPreKeyIDAfterUpload)
	}

	public var nextPreKeyIDAfterUpload: Int {
		firstUnuploadedPreKeyID + max(requestedUploadCount, 0)
	}

	public init(
		localJID: String? = nil,
		localAddress: SignalProtocolAddress? = nil,
		currentServerPreKeyCount: Int? = nil,
		registrationID: Int,
		identityPrivateKey: Data,
		identityCurve25519PublicKey: Data,
		signedPreKeyID: Int,
		signedPreKeyPrivateKey: Data,
		signedPreKeyCurve25519PublicKey: Data,
		signedPreKeySignature: Data,
		firstUnuploadedPreKeyID: Int,
		requestedUploadCount: Int
	) {
		self.localJID = localJID
		self.localAddress = localAddress
		self.currentServerPreKeyCount = currentServerPreKeyCount
		self.registrationID = registrationID
		self.identityPrivateKey = identityPrivateKey
		self.identityCurve25519PublicKey = identityCurve25519PublicKey
		self.signedPreKeyID = signedPreKeyID
		self.signedPreKeyPrivateKey = signedPreKeyPrivateKey
		self.signedPreKeyCurve25519PublicKey = signedPreKeyCurve25519PublicKey
		self.signedPreKeySignature = signedPreKeySignature
		self.firstUnuploadedPreKeyID = firstUnuploadedPreKeyID
		self.requestedUploadCount = requestedUploadCount
	}

	public func validate() throws {
		if let localJID {
			guard SignalProtocolAddress(jid: localJID) == localAddress else {
				throw SignalNativePreKeyUploadRequestError.invalidLocalJID
			}
		} else if localAddress != nil {
			throw SignalNativePreKeyUploadRequestError.invalidLocalJID
		}
		guard identityCurve25519PublicKey.count == 32,
			  signedPreKeyCurve25519PublicKey.count == 32,
			  signedPreKeySignature.count == 64 else {
			throw SignalNativePreKeyUploadRequestError.invalidKeyMaterial
		}
		guard (1...0xFF_FF_FF).contains(signedPreKeyID) else {
			throw SignalNativePreKeyUploadRequestError.invalidKeyID
		}
		if requestedUploadCount > 0 {
			guard (1...0xFF_FF_FF).contains(firstUnuploadedPreKeyID),
				  requestedUploadCount <= 0xFF_FF_FF - firstUnuploadedPreKeyID + 1 else {
				throw SignalNativePreKeyUploadRequestError.invalidKeyID
			}
		}
	}
}

public extension AuthenticationCredentials {
	func nativePreKeyUploadRequest(
		currentServerPreKeyCount: Int? = nil,
		requestedUploadCount: Int
	) throws -> SignalNativePreKeyUploadRequest {
		guard requestedUploadCount > 0 else {
			throw SignalNativePreKeyUploadRequestError.invalidRequestedUploadCount
		}

		let keyMaterial: SignalNativeAccountKeyMaterial
		do {
			keyMaterial = try nativeAccountKeyMaterial()
		} catch SignalNativeKeyMaterialError.invalidKeyMaterial {
			throw SignalNativePreKeyUploadRequestError.invalidKeyMaterial
		} catch SignalNativeKeyMaterialError.invalidKeyID {
			throw SignalNativePreKeyUploadRequestError.invalidKeyID
		} catch {
			throw error
		}

		let localJID = me?.id
		let localAddress: SignalProtocolAddress?
		if let localJID {
			guard let address = SignalProtocolAddress(jid: localJID) else {
				throw SignalNativePreKeyUploadRequestError.invalidLocalJID
			}
			localAddress = address
		} else {
			localAddress = nil
		}

		let request = SignalNativePreKeyUploadRequest(
			localJID: localJID,
			localAddress: localAddress,
			currentServerPreKeyCount: currentServerPreKeyCount,
			registrationID: keyMaterial.registrationID,
			identityPrivateKey: keyMaterial.identityPrivateKey,
			identityCurve25519PublicKey: keyMaterial.identityCurve25519PublicKey,
			signedPreKeyID: keyMaterial.signedPreKeyID,
			signedPreKeyPrivateKey: keyMaterial.signedPreKeyPrivateKey,
			signedPreKeyCurve25519PublicKey: keyMaterial.signedPreKeyCurve25519PublicKey,
			signedPreKeySignature: keyMaterial.signedPreKeySignature,
			firstUnuploadedPreKeyID: firstUnuploadedPreKeyID,
			requestedUploadCount: requestedUploadCount
		)
		try request.validate()
		return request
	}
}

public enum SignalNativePreKeyUploadRequestError: Error, Equatable, Sendable {
	case invalidKeyID
	case invalidKeyMaterial
	case invalidLocalJID
	case invalidRequestedUploadCount
}

enum PreKeyUploadRequestBuilder {
	static func build(
		credentials: AuthenticationCredentials,
		count: Int,
		requestID: String,
		keyPairGenerator: () throws -> AuthenticationKeyPair
	) throws -> PreKeyUploadRequest {
		guard count > 0 else {
			throw PreKeyUploadRequestError.invalidRequestedUploadCount
		}
		guard let identityPublicKey = curve25519PublicKey(credentials.signedIdentityKey.publicKey),
			  let signedPreKeyPublicKey = curve25519PublicKey(credentials.signedPreKey.keyPair.publicKey) else {
			throw PreKeyUploadRequestError.invalidKeyMaterial
		}
		guard credentials.signedPreKey.signature.count == 64 else {
			throw PreKeyUploadRequestError.invalidKeyMaterial
		}
		guard (1...0xFF_FF_FF).contains(credentials.signedPreKey.keyID) else {
			throw PreKeyUploadRequestError.invalidKeyID
		}

		let startID = credentials.firstUnuploadedPreKeyID
		guard (1...0xFF_FF_FF).contains(startID),
			  count <= 0xFF_FF_FF - startID + 1 else {
			throw PreKeyUploadRequestError.invalidKeyID
		}
		let endID = startID + count
		var storedPreKeys: [String: StoredPreKey] = [:]
		var preKeyNodes: [BinaryNode] = []

		for keyID in startID..<endID {
			let keyPair = try keyPairGenerator()
			guard keyPair.privateKey.count == 32, keyPair.publicKey.count == 32 else {
				throw PreKeyUploadRequestError.invalidKeyMaterial
			}
			storedPreKeys[String(keyID)] = StoredPreKey(
				privateKey: keyPair.privateKey,
				publicKey: keyPair.publicKey
			)
			preKeyNodes.append(xmppPreKey(keyPair: keyPair, keyID: keyID))
		}

		let lastPreKeyID = endID - 1
		return PreKeyUploadRequest(
			node: BinaryNode(
				tag: "iq",
				attrs: ["id": requestID, "xmlns": "encrypt", "type": "set", "to": "@s.whatsapp.net"],
				content: .nodes([
					BinaryNode(tag: "registration", content: .data(BigEndianEncoder.encode(credentials.registrationID, count: 4))),
					BinaryNode(tag: "type", content: .data(Data([5]))),
					BinaryNode(tag: "identity", content: .data(identityPublicKey)),
					BinaryNode(tag: "list", content: .nodes(preKeyNodes)),
					xmppSignedPreKey(credentials.signedPreKey, publicKey: signedPreKeyPublicKey)
				])
			),
			preKeys: storedPreKeys,
			nextPreKeyID: max(lastPreKeyID + 1, credentials.nextPreKeyID),
			firstUnuploadedPreKeyID: max(credentials.firstUnuploadedPreKeyID, lastPreKeyID + 1)
		)
	}

	static func encode(_ preKey: StoredPreKey) throws -> Data {
		try JSONEncoder().encode(preKey)
	}

	private static func xmppPreKey(keyPair: AuthenticationKeyPair, keyID: Int) -> BinaryNode {
		BinaryNode(
			tag: "key",
			content: .nodes([
				BinaryNode(tag: "id", content: .data(BigEndianEncoder.encode(keyID, count: 3))),
				BinaryNode(tag: "value", content: .data(keyPair.publicKey))
			])
		)
	}

	private static func xmppSignedPreKey(_ key: SignedAuthenticationKeyPair, publicKey: Data) -> BinaryNode {
		BinaryNode(
			tag: "skey",
			content: .nodes([
				BinaryNode(tag: "id", content: .data(BigEndianEncoder.encode(key.keyID, count: 3))),
				BinaryNode(tag: "value", content: .data(publicKey)),
				BinaryNode(tag: "signature", content: .data(key.signature))
			])
		)
	}

	private static func curve25519PublicKey(_ publicKey: Data) -> Data? {
		if publicKey.count == 32 {
			return publicKey
		}
		if publicKey.count == 33, publicKey.first == 5 {
			return publicKey.dropFirst()
		}
		return nil
	}
}
