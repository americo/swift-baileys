import Foundation

extension WhatsAppClient {
	@discardableResult
	public func sendRetryRequest(
		for node: BinaryNode,
		forceIncludeKeys: Bool = false
	) async throws -> BinaryNode? {
		guard let authenticationState else {
			throw WhatsAppClientError.missingAuthenticationState
		}
		guard let messageID = node.attrs["id"], !messageID.isEmpty else {
			throw WhatsAppClientError.missingRequestID
		}
		guard let from = node.attrs["from"], !from.isEmpty else {
			throw WhatsAppClientError.missingMessageDestination
		}
		guard let timestamp = node.attrs["t"], !timestamp.isEmpty else {
			throw WhatsAppClientError.missingRetryTimestamp
		}

		let participant = node.attrs["participant"]
		let retryKey = RetryResendKey(
			destinationJID: from,
			messageID: messageID,
			requesterJID: participant ?? from
		)
		let currentCount = retryResendCounts[retryKey] ?? 0
		guard currentCount < configuration.maxMessageRetryCount else {
			return nil
		}

		let retryCount = currentCount + 1
		retryResendCounts[retryKey] = retryCount
		let includeKeys = forceIncludeKeys || retryCount > 1
		let keyBundle = includeKeys ? try await makeRetryKeyBundle(authenticationState: authenticationState) : nil
		let receipt = try RetryRequestReceiptBuilder.build(
			for: node,
			messageID: messageID,
			from: from,
			timestamp: timestamp,
			retryCount: retryCount,
			registrationID: authenticationState.credentials.registrationID,
			keyBundle: keyBundle
		)

		try await sendNode(receipt)
		return receipt
	}

	private func makeRetryKeyBundle(authenticationState: AuthenticationState) async throws -> RetryRequestKeyBundle {
		guard let account = authenticationState.credentials.account else {
			throw WhatsAppClientError.missingAuthenticatedUser
		}
		guard let identityPublicKey = RetryRequestReceiptBuilder.curve25519PublicKey(
			authenticationState.credentials.signedIdentityKey.publicKey
		),
			  let signedPreKeyPublicKey = RetryRequestReceiptBuilder.curve25519PublicKey(
			  	authenticationState.credentials.signedPreKey.keyPair.publicKey
			  ) else {
			throw PreKeyUploadRequestError.invalidKeyMaterial
		}

		let preKeyID = authenticationState.credentials.firstUnuploadedPreKeyID
		guard (1...0xFF_FF_FF).contains(preKeyID) else {
			throw PreKeyUploadRequestError.invalidKeyID
		}
		let preKey = try preKeyGenerator()
		guard preKey.privateKey.count == 32, preKey.publicKey.count == 32 else {
			throw PreKeyUploadRequestError.invalidKeyMaterial
		}

		let stored = StoredPreKey(privateKey: preKey.privateKey, publicKey: preKey.publicKey)
		try await authenticationState.keys.set([
			.preKey: [String(preKeyID): try PreKeyUploadRequestBuilder.encode(stored)]
		])
		try await updateCredentials { credentials in
			credentials.nextPreKeyID = max(credentials.nextPreKeyID, preKeyID + 1)
			credentials.firstUnuploadedPreKeyID = preKeyID + 1
		}

		return RetryRequestKeyBundle(
			identityPublicKey: identityPublicKey,
			preKeyID: preKeyID,
			preKeyPublicKey: preKey.publicKey,
			signedPreKey: authenticationState.credentials.signedPreKey,
			signedPreKeyPublicKey: signedPreKeyPublicKey,
			deviceIdentity: try RetryRequestReceiptBuilder.encodeSignedDeviceIdentity(account)
		)
	}
}

private struct RetryRequestKeyBundle: Equatable, Sendable {
	let identityPublicKey: Data
	let preKeyID: Int
	let preKeyPublicKey: Data
	let signedPreKey: SignedAuthenticationKeyPair
	let signedPreKeyPublicKey: Data
	let deviceIdentity: Data
}

private enum RetryRequestReceiptBuilder {
	static func build(
		for node: BinaryNode,
		messageID: String,
		from: String,
		timestamp: String,
		retryCount: Int,
		registrationID: Int,
		keyBundle: RetryRequestKeyBundle?
	) throws -> BinaryNode {
		var attrs = [("id", messageID), ("type", "retry"), ("to", from)]
		if let recipient = node.attrs["recipient"] {
			attrs.append(("recipient", recipient))
		}
		if let participant = node.attrs["participant"] {
			attrs.append(("participant", participant))
		}

		var content = [
			BinaryNode(
				tag: "retry",
				attrs: [
					"count": String(retryCount),
					"id": messageID,
					"t": timestamp,
					"v": "1",
					"error": "0"
				]
			),
			BinaryNode(tag: "registration", content: .data(BigEndianEncoder.encode(registrationID, count: 4)))
		]
		if let keyBundle {
			content.append(try keysNode(from: keyBundle))
		}

		return BinaryNode(tag: "receipt", attrs: BinaryNodeAttributes(attrs), content: .nodes(content))
	}

	static func curve25519PublicKey(_ publicKey: Data) -> Data? {
		if publicKey.count == 32 {
			return publicKey
		}
		if publicKey.count == 33, publicKey.first == 5 {
			return publicKey.dropFirst()
		}
		return nil
	}

	static func encodeSignedDeviceIdentity(_ account: SignedDeviceIdentityAccount) throws -> Data {
		var proto = Proto_ADVSignedDeviceIdentity()
		proto.details = account.details
		if !account.accountSignatureKey.isEmpty {
			proto.accountSignatureKey = account.accountSignatureKey
		}
		proto.accountSignature = account.accountSignature
		if let deviceSignature = account.deviceSignature {
			proto.deviceSignature = deviceSignature
		}
		return try proto.serializedData()
	}

	private static func keysNode(from bundle: RetryRequestKeyBundle) throws -> BinaryNode {
		BinaryNode(tag: "keys", content: .nodes([
			BinaryNode(tag: "type", content: .data(Data([5]))),
			BinaryNode(tag: "identity", content: .data(bundle.identityPublicKey)),
			xmppPreKey(id: bundle.preKeyID, publicKey: bundle.preKeyPublicKey),
			xmppSignedPreKey(bundle.signedPreKey, publicKey: bundle.signedPreKeyPublicKey),
			BinaryNode(tag: "device-identity", content: .data(bundle.deviceIdentity))
		]))
	}

	private static func xmppPreKey(id: Int, publicKey: Data) -> BinaryNode {
		BinaryNode(tag: "key", content: .nodes([
			BinaryNode(tag: "id", content: .data(BigEndianEncoder.encode(id, count: 3))),
			BinaryNode(tag: "value", content: .data(publicKey))
		]))
	}

	private static func xmppSignedPreKey(_ key: SignedAuthenticationKeyPair, publicKey: Data) -> BinaryNode {
		BinaryNode(tag: "skey", content: .nodes([
			BinaryNode(tag: "id", content: .data(BigEndianEncoder.encode(key.keyID, count: 3))),
			BinaryNode(tag: "value", content: .data(publicKey)),
			BinaryNode(tag: "signature", content: .data(key.signature))
		]))
	}
}
