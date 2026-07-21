import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client privacy-token regular-user gates")
struct WhatsAppClientPrivacyTokenRegularUserTests {
	@Test("does not store trusted contact tokens for PSA JIDs")
	func doesNotStoreTrustedContactTokensForPSAJIDs() async throws {
		let transport = MockProfileWebSocketTransport()
		let keys = InMemorySignalKeyStore()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: privacyTokenRegularUserCredentials(), keys: keys),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let task = Task {
			try await client.issuePrivacyTokens(
				for: ["0@c.us"],
				timestamp: 1_700_000_001,
				requestID: "privacy-psa-1"
			)
		}
		_ = try await transport.waitForSentNode()
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "privacy-psa-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "tokens", content: .nodes([
					BinaryNode(
						tag: "token",
						attrs: ["type": "trusted_contact", "t": "1700000002"],
						content: .data(Data([0x01, 0x02]))
					)
				]))
			])
		))
		_ = try await task.value

		#expect(try await keys.get(.tcToken, ids: ["0@s.whatsapp.net"])["0@s.whatsapp.net"] == nil)
	}

	@Test("does not store incoming privacy-token notifications for PSA JIDs")
	func doesNotStoreIncomingPrivacyTokenNotificationsForPSAJIDs() async throws {
		let keys = InMemorySignalKeyStore()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: privacyTokenRegularUserCredentials(), keys: keys)
		)

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["id": "privacy-psa-notification-1", "from": "0@c.us", "type": "privacy_token"],
			content: .nodes([
				BinaryNode(tag: "tokens", content: .nodes([
					BinaryNode(
						tag: "token",
						attrs: ["type": "trusted_contact", "t": "1700000002"],
						content: .data(Data([0x03, 0x04]))
					)
				]))
			])
		))

		#expect(try await keys.get(.tcToken, ids: ["0@s.whatsapp.net"])["0@s.whatsapp.net"] == nil)
	}

	@Test("does not issue trusted contact tokens after sending to PSA JIDs")
	func doesNotIssueTrustedContactTokensAfterSendingToPSAJIDs() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: privacyTokenRegularUserCredentials(), keys: InMemorySignalKeyStore()),
			transportFactory: { _ in transport },
			messageEncryptor: StubMessageSendEncryptor(
				results: [EncryptedMessage(type: "msg", ciphertext: Data([0x10]))],
				callOrder: callOrder
			),
			messageDeviceResolver: StubMessageDeviceResolver(result: ["0.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		_ = try await client.sendTextMessage(to: "0@c.us", text: "hello", messageID: "3EB0PSATCTOKEN")
		try await Task.sleep(for: .milliseconds(25))

		#expect(await transport.sentFrames.count == 1)
	}
}

private func privacyTokenRegularUserCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32)),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data(repeating: 3, count: 32), publicKey: Data(repeating: 4, count: 32)),
		signedIdentityKey: AuthenticationKeyPair(privateKey: Data(repeating: 5, count: 32), publicKey: Data(repeating: 6, count: 32)),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(privateKey: Data(repeating: 7, count: 32), publicKey: Data(repeating: 8, count: 32)),
			signature: Data(repeating: 9, count: 64),
			keyID: 1
		),
		registrationID: 1,
		advSecretKey: "adv-secret",
		me: WhatsAppUser(id: "999@s.whatsapp.net"),
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true
	)
}
