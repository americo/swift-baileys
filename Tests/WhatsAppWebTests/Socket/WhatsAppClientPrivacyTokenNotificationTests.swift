import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client privacy-token notifications")
struct WhatsAppClientPrivacyTokenNotificationTests {
	@Test("stores trusted contact tokens under sender LID and acknowledges the notification")
	func storesTrustedContactTokenUnderSenderLID() async throws {
		let transport = MockProfileWebSocketTransport()
		let keys = InMemorySignalKeyStore()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePrivacyTokenCredentials(),
				keys: keys
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		await client.handleIncomingNode(privacyTokenNotification(
			id: "privacy-1",
			from: "258840000000@s.whatsapp.net",
			senderLID: "123456789@lid",
			token: Data([1, 2, 3, 4]),
			timestamp: "200"
		))

		let storedData = try #require(await keys.get(.tcToken, ids: ["123456789@lid"])["123456789@lid"])
		#expect(try TrustedContactTokenCoding.decode(storedData) == TrustedContactToken(
			token: Data([1, 2, 3, 4]),
			timestamp: "200"
		))
		let indexData = try #require(await keys.get(.tcToken, ids: [TrustedContactTokenCoding.indexKey])[TrustedContactTokenCoding.indexKey])
		#expect(try TrustedContactTokenCoding.decodeIndex(indexData) == ["123456789@lid"])
		let ack = try await transport.waitForSentNode()
		#expect(ack.tag == "ack")
		#expect(ack.attrs["id"] == "privacy-1")
		#expect(ack.attrs["class"] == "notification")
		#expect(ack.attrs["type"] == "privacy_token")
	}

	@Test("keeps a newer existing trusted contact token")
	func keepsNewerExistingTrustedContactToken() async throws {
		let keys = InMemorySignalKeyStore(storage: [
			.tcToken: [
				"258840000000@s.whatsapp.net": try TrustedContactTokenCoding.encode(TrustedContactToken(
					token: Data([9, 9]),
					timestamp: "300",
					senderTimestamp: "250"
				))
			]
		])
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: samplePrivacyTokenCredentials(),
				keys: keys
			)
		)

		await client.handleIncomingNode(privacyTokenNotification(
			id: "privacy-2",
			from: "258840000000@c.us",
			token: Data([1, 2]),
			timestamp: "200"
		))

		let storedData = try #require(await keys.get(.tcToken, ids: ["258840000000@s.whatsapp.net"])["258840000000@s.whatsapp.net"])
		#expect(try TrustedContactTokenCoding.decode(storedData) == TrustedContactToken(
			token: Data([9, 9]),
			timestamp: "300",
			senderTimestamp: "250"
		))
	}
}

private func privacyTokenNotification(
	id: String,
	from: String,
	senderLID: String? = nil,
	token: Data,
	timestamp: String
) -> BinaryNode {
	var attrs: [(String, String)] = [
		("id", id),
		("from", from),
		("type", "privacy_token")
	]
	if let senderLID {
		attrs.append(("sender_lid", senderLID))
	}

	return BinaryNode(
		tag: "notification",
		attrs: BinaryNodeAttributes(attrs),
		content: .nodes([
			BinaryNode(
				tag: "tokens",
				content: .nodes([
					BinaryNode(
						tag: "token",
						attrs: ["type": "trusted_contact", "t": timestamp],
						content: .data(token)
					)
				])
			)
		])
	)
}

private func samplePrivacyTokenCredentials() -> AuthenticationCredentials {
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
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true
	)
}
