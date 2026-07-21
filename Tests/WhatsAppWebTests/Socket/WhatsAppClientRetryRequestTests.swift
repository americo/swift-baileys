import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client retry requests")
struct WhatsAppClientRetryRequestTests {
	@Test("Baileys sendRetryRequest alias sends retry receipts")
	func baileysSendRetryRequestAliasSendsRetryReceipts() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: retryRequestCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let receipt = try await client.sendRetryRequest(for: failedMessageNode())
		let sent = try await decodeSentNode(from: transport)

		#expect(receipt == sent)
		#expect(sent.attrs["id"] == "retry-msg-1")
		#expect(sent.attrs["type"] == "retry")
		#expect(sent.attrs["to"] == "123@s.whatsapp.net")
		#expect(sent.attrs["participant"] == "456@s.whatsapp.net")
		let retry = try #require(sent.firstChild(named: "retry"))
		#expect(retry.attrs["count"] == "1")
		#expect(retry.attrs["id"] == "retry-msg-1")
		#expect(retry.attrs["t"] == "1718000000")
		#expect(retry.attrs["v"] == "1")
		#expect(retry.attrs["error"] == "0")
		#expect(sent.childData(named: "registration") == Data([0, 0, 2, 47]))
		#expect(sent.firstChild(named: "keys") == nil)
	}

	@Test("Baileys sendRetryRequest alias can include retry key bundles")
	func baileysSendRetryRequestAliasCanIncludeRetryKeyBundles() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let keys = InMemorySignalKeyStore()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: retryRequestCredentials(), keys: keys),
			transportFactory: { _ in transport },
			preKeyGenerator: { AuthenticationKeyPair(
				privateKey: Data(repeating: 0xa1, count: 32),
				publicKey: Data(repeating: 0xb2, count: 32)
			) }
		)
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		let sent = try await client.sendRetryRequest(for: failedMessageNode(), forceIncludeKeys: true)
		_ = try await transport.waitForSentFrame()
		let keysNode = try #require(sent?.firstChild(named: "keys"))

		#expect(keysNode.childData(named: "type") == Data([5]))
		#expect(keysNode.childData(named: "identity") == Data(repeating: 0x09, count: 32))
		let preKey = try #require(keysNode.firstChild(named: "key"))
		#expect(preKey.childData(named: "id") == Data([0, 0, 7]))
		#expect(preKey.childData(named: "value") == Data(repeating: 0xb2, count: 32))
		let signedPreKey = try #require(keysNode.firstChild(named: "skey"))
		#expect(signedPreKey.childData(named: "id") == Data([0, 0, 1]))
		#expect(signedPreKey.childData(named: "value") == Data(repeating: 0x08, count: 32))
		#expect(signedPreKey.childData(named: "signature") == Data(repeating: 0x07, count: 64))
		let deviceIdentity = try Proto_ADVSignedDeviceIdentity(
			serializedBytes: try #require(keysNode.childData(named: "device-identity"))
		)
		#expect(deviceIdentity.details == Data([0x01, 0x02, 0x03]))
		#expect(deviceIdentity.accountSignatureKey == Data(repeating: 0x44, count: 32))
		#expect(deviceIdentity.accountSignature == Data(repeating: 0x55, count: 64))

		let stored = try await keys.get(.preKey, ids: ["7"])
		#expect(try JSONDecoder().decode(StoredPreKey.self, from: try #require(stored["7"])) == StoredPreKey(
			privateKey: Data(repeating: 0xa1, count: 32),
			publicKey: Data(repeating: 0xb2, count: 32)
		))
		let updated = try #require(await client.authenticationState?.credentials)
		#expect(updated.nextPreKeyID == 8)
		#expect(updated.firstUnuploadedPreKeyID == 8)
		#expect(await events.next() == .credentialsUpdated(updated))
	}
}

private func failedMessageNode() -> BinaryNode {
	BinaryNode(
		tag: "message",
		attrs: [
			"id": "retry-msg-1",
			"from": "123@s.whatsapp.net",
			"participant": "456@s.whatsapp.net",
			"t": "1718000000"
		]
	)
}

private func decodeSentNode(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	let sentFrame = try await transport.waitForSentFrame()
	var codec = NoiseFrameCodec()
	return try BinaryNodeDecoder().decode(codec.decode(sentFrame)[0])
}

private func retryRequestCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data(repeating: 0x01, count: 32), publicKey: Data(repeating: 0x02, count: 32)),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data(repeating: 0x03, count: 32), publicKey: Data(repeating: 0x04, count: 32)),
		signedIdentityKey: AuthenticationKeyPair(privateKey: Data(repeating: 0x05, count: 32), publicKey: Data(repeating: 0x09, count: 32)),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(privateKey: Data(repeating: 0x06, count: 32), publicKey: Data(repeating: 0x08, count: 32)),
			signature: Data(repeating: 0x07, count: 64),
			keyID: 1
		),
		registrationID: 559,
		advSecretKey: "adv-secret",
		me: WhatsAppUser(id: "999@s.whatsapp.net", name: "Swift"),
		account: SignedDeviceIdentityAccount(
			details: Data([0x01, 0x02, 0x03]),
			accountSignatureKey: Data(repeating: 0x44, count: 32),
			accountSignature: Data(repeating: 0x55, count: 64),
			deviceSignature: Data(repeating: 0x66, count: 64)
		),
		nextPreKeyID: 7,
		firstUnuploadedPreKeyID: 7,
		accountSyncCounter: 0,
		registered: true
	)
}
