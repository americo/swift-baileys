private let initialPreKeyCount = 812

public enum PreKeyCountQueryError: Error, Equatable, Sendable {
	case missingCount
}

public enum PreKeyDigestError: Error, Equatable, Sendable {
	case missingDigest
}

public struct CurrentPreKeyState: Equatable, Sendable {
	public let exists: Bool
	public let currentPreKeyID: Int

	public init(exists: Bool, currentPreKeyID: Int) {
		self.exists = exists
		self.currentPreKeyID = currentPreKeyID
	}
}

public struct PreKeyServerUploadCheckResult: Equatable, Sendable {
	public let serverPreKeyCount: Int
	public let currentPreKeyExists: Bool
	public let currentPreKeyID: Int
	public let requestedUploadCount: Int?

	public var didUpload: Bool {
		requestedUploadCount != nil
	}

	public init(
		serverPreKeyCount: Int,
		currentPreKeyExists: Bool,
		currentPreKeyID: Int,
		requestedUploadCount: Int?
	) {
		self.serverPreKeyCount = serverPreKeyCount
		self.currentPreKeyExists = currentPreKeyExists
		self.currentPreKeyID = currentPreKeyID
		self.requestedUploadCount = requestedUploadCount
	}
}

extension WhatsAppClient {
	public func getAvailablePreKeysOnServer(requestID: String? = nil) async throws -> Int {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"xmlns": "encrypt",
				"type": "get",
				"to": "@s.whatsapp.net"
			],
			content: .nodes([
				BinaryNode(tag: "count")
			])
		))

		guard let count = result.firstChild(named: "count")?.attrs["value"].flatMap(Int.init) else {
			throw PreKeyCountQueryError.missingCount
		}

		return count
	}

	public func verifyCurrentPreKeyExists() async throws -> CurrentPreKeyState {
		guard let authenticationState else {
			throw WhatsAppClientError.missingAuthenticationState
		}

		let currentPreKeyID = authenticationState.credentials.nextPreKeyID - 1
		guard currentPreKeyID > 0 else {
			return CurrentPreKeyState(exists: false, currentPreKeyID: 0)
		}

		let preKeys = try await authenticationState.keys.get(.preKey, ids: [String(currentPreKeyID)])
		return CurrentPreKeyState(exists: preKeys[String(currentPreKeyID)] != nil, currentPreKeyID: currentPreKeyID)
	}

	public func uploadPreKeysToServerIfRequired(requestID: String? = nil) async throws -> PreKeyServerUploadCheckResult {
		let serverPreKeyCount = try await getAvailablePreKeysOnServer(requestID: requestID)
		let requestedUploadCount = serverPreKeyCount == 0 ? initialPreKeyCount : minimumPreKeyCount
		let currentPreKeyState = try await verifyCurrentPreKeyExists()
		let lowServerCount = serverPreKeyCount <= requestedUploadCount
		let missingCurrentPreKey = !currentPreKeyState.exists && currentPreKeyState.currentPreKeyID > 0

		guard lowServerCount || missingCurrentPreKey else {
			return PreKeyServerUploadCheckResult(
				serverPreKeyCount: serverPreKeyCount,
				currentPreKeyExists: currentPreKeyState.exists,
				currentPreKeyID: currentPreKeyState.currentPreKeyID,
				requestedUploadCount: nil
			)
		}

		if let preKeyUploader {
			if let signalPreKeyUploader = preKeyUploader as? any SignalPreKeyUploading {
				try await signalPreKeyUploader.uploadPreKeys(SignalPreKeyUploadRequest(
					currentCount: serverPreKeyCount,
					requestedUploadCount: requestedUploadCount,
					nativeUploadRequest: try authenticationState?.credentials.nativePreKeyUploadRequest(
						currentServerPreKeyCount: serverPreKeyCount,
						requestedUploadCount: requestedUploadCount
					)
				))
			} else {
				try await preKeyUploader.uploadPreKeys(count: requestedUploadCount)
			}
		} else {
			try await uploadPreKeys(count: requestedUploadCount)
		}

		return PreKeyServerUploadCheckResult(
			serverPreKeyCount: serverPreKeyCount,
			currentPreKeyExists: currentPreKeyState.exists,
			currentPreKeyID: currentPreKeyState.currentPreKeyID,
			requestedUploadCount: requestedUploadCount
		)
	}

	public func digestKeyBundle(requestID: String? = nil) async throws {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"to": "@s.whatsapp.net",
				"type": "get",
				"xmlns": "encrypt"
			],
			content: .nodes([
				BinaryNode(tag: "digest")
			])
		))

		guard result.firstChild(named: "digest") != nil else {
			if let preKeyUploader {
				if let signalPreKeyUploader = preKeyUploader as? any SignalPreKeyUploading {
					try await signalPreKeyUploader.uploadPreKeys(SignalPreKeyUploadRequest(
						requestedUploadCount: minimumPreKeyCount,
						nativeUploadRequest: try authenticationState?.credentials.nativePreKeyUploadRequest(
							requestedUploadCount: minimumPreKeyCount
						)
					))
				} else {
					try await preKeyUploader.uploadPreKeys(count: minimumPreKeyCount)
				}
			} else {
				try await uploadPreKeys(count: minimumPreKeyCount)
			}
			throw PreKeyDigestError.missingDigest
		}
	}

	public func configureSignedPreKeySigner(_ signer: any SignalSignedPreKeySigning) {
		signedPreKeySigner = signer
	}

	public func rotateSignedPreKey(requestID: String? = nil) async throws {
		guard let authenticationState else {
			throw WhatsAppClientError.missingAuthenticationState
		}
		guard let signedPreKeySigner else {
			throw WhatsAppClientError.missingSignedPreKeySigner
		}

		let keyID = authenticationState.credentials.signedPreKey.keyID + 1
		let signedPreKey = try SignalSignedKeyPairFactory.make(
			identityKeyPair: authenticationState.credentials.signedIdentityKey,
			keyID: keyID,
			keyPairGenerator: preKeyGenerator,
			signer: signedPreKeySigner.signSignedPreKey
		)
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState.credentials.me?.id)

		_ = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"to": "@s.whatsapp.net",
				"type": "set",
				"xmlns": "encrypt"
			],
			content: .nodes([
				BinaryNode(
					tag: "rotate",
					content: .nodes([
						BinaryNode(
							tag: "skey",
							content: .nodes([
								BinaryNode(tag: "id", content: .data(BigEndianEncoder.encode(signedPreKey.keyID, count: 3))),
								BinaryNode(tag: "value", content: .data(signedPreKey.keyPair.publicKey)),
								BinaryNode(tag: "signature", content: .data(signedPreKey.signature))
							])
						)
					])
				)
			])
		))

		try await updateCredentials { credentials in
			credentials.signedPreKey = signedPreKey
		}
	}
}
