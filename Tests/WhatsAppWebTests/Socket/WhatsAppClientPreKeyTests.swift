import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client pre-key startup checks")
struct WhatsAppClientPreKeyTests {
	@Test("uploads initial pre-key batch when server has no pre-keys")
	func uploadsInitialPreKeyBatchWhenServerHasNoPreKeys() async throws {
		let transport = MockProfileWebSocketTransport()
		let uploader = RecordingPreKeyUploader()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePreKeyStartupCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport },
			preKeyUploader: uploader
		)
		try await client.connect()

		let task = Task {
			try await client.uploadPreKeysToServerIfRequired(requestID: "pre-key-startup-zero")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "pre-key-startup-zero")
		#expect(request.attrs["xmlns"] == "encrypt")
		#expect(request.firstChild(named: "count") != nil)
		await transport.enqueueInbound(preKeyCountResponse(id: "pre-key-startup-zero", value: 0))

		let result = try await task.value
		#expect(result.serverPreKeyCount == 0)
		#expect(result.currentPreKeyID == 7)
		#expect(result.currentPreKeyExists == false)
		#expect(result.requestedUploadCount == 812)
		#expect(result.didUpload)
		#expect(await uploader.uploadedCounts() == [812])
	}

	@Test("skips upload when server count is healthy and current pre-key exists")
	func skipsUploadWhenServerCountIsHealthyAndCurrentPreKeyExists() async throws {
		let transport = MockProfileWebSocketTransport()
		let uploader = RecordingPreKeyUploader()
		let keys = InMemorySignalKeyStore(storage: [.preKey: ["7": Data([7])]])
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePreKeyStartupCredentials(),
				keys: keys
			),
			transportFactory: { _ in transport },
			preKeyUploader: uploader
		)
		try await client.connect()

		let task = Task {
			try await client.uploadPreKeysToServerIfRequired(requestID: "pre-key-startup-healthy")
		}
		_ = try await transport.waitForSentNode()
		await transport.enqueueInbound(preKeyCountResponse(id: "pre-key-startup-healthy", value: 10))

		let result = try await task.value
		#expect(result.serverPreKeyCount == 10)
		#expect(result.currentPreKeyID == 7)
		#expect(result.currentPreKeyExists)
		#expect(result.requestedUploadCount == nil)
		#expect(!result.didUpload)
		#expect(await uploader.uploadedCounts().isEmpty)
	}

	@Test("uploads minimum batch when current local pre-key is missing")
	func uploadsMinimumBatchWhenCurrentLocalPreKeyIsMissing() async throws {
		let transport = MockProfileWebSocketTransport()
		let uploader = RecordingPreKeyUploader()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePreKeyStartupCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport },
			preKeyUploader: uploader
		)
		try await client.connect()

		let task = Task {
			try await client.uploadPreKeysToServerIfRequired(requestID: "pre-key-startup-missing-local")
		}
		_ = try await transport.waitForSentNode()
		await transport.enqueueInbound(preKeyCountResponse(id: "pre-key-startup-missing-local", value: 10))

		let result = try await task.value
		#expect(result.serverPreKeyCount == 10)
		#expect(result.currentPreKeyID == 7)
		#expect(result.currentPreKeyExists == false)
		#expect(result.requestedUploadCount == 5)
		#expect(result.didUpload)
		#expect(await uploader.uploadedCounts() == [5])
	}

	@Test("Baileys digestKeyBundle alias accepts digest responses")
	func baileysDigestKeyBundleAliasAcceptsDigestResponses() async throws {
		let transport = MockProfileWebSocketTransport()
		let uploader = RecordingPreKeyUploader()
		let client = WhatsAppClient(transportFactory: { _ in transport }, preKeyUploader: uploader)
		try await client.connect()

		let task = Task {
			try await client.digestKeyBundle(requestID: "digest-ok")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "digest-ok")
		#expect(request.attrs["xmlns"] == "encrypt")
		#expect(request.firstChild(named: "digest") != nil)
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "digest-ok", "type": "result"],
			content: .nodes([BinaryNode(tag: "digest")])
		))

		try await task.value
		#expect(await uploader.uploadedCounts().isEmpty)
	}

	@Test("Baileys digestKeyBundle alias uploads prekeys and throws when digest is missing")
	func baileysDigestKeyBundleAliasUploadsPreKeysAndThrowsWhenDigestIsMissing() async throws {
		let transport = MockProfileWebSocketTransport()
		let uploader = RecordingPreKeyUploader()
		let client = WhatsAppClient(transportFactory: { _ in transport }, preKeyUploader: uploader)
		try await client.connect()

		let task = Task {
			try await client.digestKeyBundle(requestID: "digest-missing")
		}
		_ = try await transport.waitForSentNode()
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "digest-missing", "type": "result"]))

		await #expect(throws: PreKeyDigestError.missingDigest) {
			try await task.value
		}
		#expect(await uploader.uploadedCounts() == [5])
	}

	@Test("Baileys rotateSignedPreKey alias sends rotate stanza and persists credentials after success")
	func baileysRotateSignedPreKeyAliasSendsRotateStanzaAndPersistsCredentialsAfterSuccess() async throws {
		let transport = MockProfileWebSocketTransport()
		let signer = RecordingSignedPreKeySigner(signature: Data(repeating: 0x09, count: 64))
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: sampleRotatableCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport },
			preKeyGenerator: {
				AuthenticationKeyPair(
					privateKey: Data(repeating: 0x03, count: 32),
					publicKey: Data(repeating: 0x04, count: 32)
				)
			}
		)
		var events = client.events.makeAsyncIterator()
		await client.configureSignedPreKeySigner(signer)
		try await client.connect()

		let task = Task {
			try await client.rotateSignedPreKey(requestID: "rotate-skey")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "rotate-skey")
		#expect(request.attrs["xmlns"] == "encrypt")
		let skey = try #require(request.firstChild(named: "rotate")?.firstChild(named: "skey"))
		#expect(skey.childData(named: "id") == Data([0x00, 0x00, 0x02]))
		#expect(skey.childData(named: "value") == Data(repeating: 0x04, count: 32))
		#expect(skey.childData(named: "signature") == Data(repeating: 0x09, count: 64))
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "rotate-skey", "type": "result"]))

		try await task.value
		let credentials = try #require(await client.authenticationState?.credentials)
		#expect(credentials.signedPreKey.keyID == 2)
		#expect(credentials.signedPreKey.keyPair.publicKey == Data(repeating: 0x04, count: 32))
		#expect(await events.next() == .credentialsUpdated(credentials))
		#expect(signer.requests() == [
			SignalSignedPreKeySignatureRequest(
				identityPrivateKey: Data(repeating: 0x01, count: 32),
				signedPreKeyPublicKey: Data(repeating: 0x04, count: 32)
			)
		])
	}

	@Test("Baileys rotateSignedPreKey alias requires a configured signer")
	func baileysRotateSignedPreKeyAliasRequiresConfiguredSigner() async {
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: sampleRotatableCredentials(),
			keys: InMemorySignalKeyStore()
		))

		await #expect(throws: WhatsAppClientError.missingSignedPreKeySigner) {
			try await client.rotateSignedPreKey(requestID: "rotate-missing-signer")
		}
	}
}

private actor RecordingPreKeyUploader: PreKeyUploading {
	private var counts: [Int] = []

	func uploadPreKeys(count: Int) async throws {
		counts.append(count)
	}

	func uploadedCounts() -> [Int] {
		counts
	}
}

private final class RecordingSignedPreKeySigner: SignalSignedPreKeySigning, @unchecked Sendable {
	private let signature: Data
	private let lock = NSLock()
	private var recordedRequests: [SignalSignedPreKeySignatureRequest] = []

	init(signature: Data) {
		self.signature = signature
	}

	func signSignedPreKey(_ request: SignalSignedPreKeySignatureRequest) throws -> Data {
		lock.withLock {
			recordedRequests.append(request)
		}
		return signature
	}

	func requests() -> [SignalSignedPreKeySignatureRequest] {
		lock.withLock {
			recordedRequests
		}
	}
}

private func preKeyCountResponse(id: String, value: Int) -> BinaryNode {
	BinaryNode(
		tag: "iq",
		attrs: ["id": id, "type": "result"],
		content: .nodes([
			BinaryNode(tag: "count", attrs: ["value": String(value)])
		])
	)
}

private func samplePreKeyStartupCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
		signedIdentityKey: AuthenticationKeyPair(
			privateKey: Data([5]),
			publicKey: Data([5]) + Data(repeating: 9, count: 32)
		),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(
				privateKey: Data([6]),
				publicKey: Data([5]) + Data(repeating: 8, count: 32)
			),
			signature: Data(repeating: 7, count: 64),
			keyID: 1
		),
		registrationID: 559,
		advSecretKey: "adv-secret",
		me: WhatsAppUser(id: "258840000000@s.whatsapp.net"),
		nextPreKeyID: 8,
		firstUnuploadedPreKeyID: 8,
		accountSyncCounter: 0,
		registered: true
	)
}

private func sampleRotatableCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
		signedIdentityKey: AuthenticationKeyPair(
			privateKey: Data(repeating: 0x01, count: 32),
			publicKey: Data(repeating: 0x02, count: 32)
		),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(
				privateKey: Data(repeating: 0x05, count: 32),
				publicKey: Data(repeating: 0x06, count: 32)
			),
			signature: Data(repeating: 0x07, count: 64),
			keyID: 1
		),
		registrationID: 559,
		advSecretKey: "adv-secret",
		me: WhatsAppUser(id: "258840000000@s.whatsapp.net"),
		nextPreKeyID: 8,
		firstUnuploadedPreKeyID: 8,
		accountSyncCounter: 0,
		registered: true
	)
}
