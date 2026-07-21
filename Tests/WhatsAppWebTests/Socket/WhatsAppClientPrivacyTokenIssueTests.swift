import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client privacy-token issue requests")
struct WhatsAppClientPrivacyTokenIssueTests {
	@Test("issues trusted contact tokens with normalized user jids")
	func issuesTrustedContactTokensWithNormalizedUserJIDs() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.issuePrivacyTokens(
				for: ["258840000000@c.us", "12345@lid"],
				timestamp: 1_700_000_001,
				requestID: "privacy-issue-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "privacy-issue-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "privacy")

		let tokens = try #require(request.firstChild(named: "tokens"))
		#expect(tokens.children(named: "token") == [
			BinaryNode(
				tag: "token",
				attrs: [
					"jid": "258840000000@s.whatsapp.net",
					"t": "1700000001",
					"type": "trusted_contact"
				]
			),
			BinaryNode(
				tag: "token",
				attrs: [
					"jid": "12345@lid",
					"t": "1700000001",
					"type": "trusted_contact"
				]
			)
		])

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "privacy-issue-1", "type": "result"]))
		_ = try await task.value
	}

	@Test("resolves LID targets to PN when the LID issuance prop is disabled")
	func resolvesLIDTargetsToPNWhenLIDIssuancePropIsDisabled() async throws {
		let transport = MockProfileWebSocketTransport()
		let keys = InMemorySignalKeyStore()
		try await LIDMappingStore.store([
			LIDMapping(pn: "258840000000@s.whatsapp.net", lid: "111222333@lid")
		], in: keys)
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: samplePrivacyTokenIssueCredentials(), keys: keys),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let task = Task {
			try await client.issuePrivacyTokens(
				for: ["111222333@lid"],
				timestamp: 1_700_000_003,
				requestID: "privacy-issue-pn"
			)
		}
		let request = try await transport.waitForSentNode()
		let tokens = try #require(request.firstChild(named: "tokens"))
		#expect(tokens.children(named: "token").first?.attrs["jid"] == "258840000000@s.whatsapp.net")

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "privacy-issue-pn", "type": "result"]))
		_ = try await task.value
	}

	@Test("resolves PN targets to LID when the LID issuance prop is enabled")
	func resolvesPNTargetsToLIDWhenLIDIssuancePropIsEnabled() async throws {
		let transport = MockProfileWebSocketTransport()
		let keys = InMemorySignalKeyStore()
		try await LIDMappingStore.store([
			LIDMapping(pn: "258840000000@s.whatsapp.net", lid: "111222333@lid")
		], in: keys)
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: samplePrivacyTokenIssueCredentials(), keys: keys),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let propsTask = Task {
			try await client.fetchProps(requestID: "props-lid-issue")
		}
		_ = try await transport.waitForSentNode(at: 0)
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "props-lid-issue", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "props", content: .nodes([
					BinaryNode(tag: "prop", attrs: ["config_code": "14303", "config_value": "true"])
				]))
			])
		))
		#expect(try await propsTask.value == ["14303": "true"])

		let task = Task {
			try await client.issuePrivacyTokens(
				for: ["258840000000@s.whatsapp.net"],
				timestamp: 1_700_000_004,
				requestID: "privacy-issue-lid"
			)
		}
		let request = try await transport.waitForSentNode(at: 1)
		let tokens = try #require(request.firstChild(named: "tokens"))
		#expect(tokens.children(named: "token").first?.attrs["jid"] == "111222333@lid")

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "privacy-issue-lid", "type": "result"]))
		_ = try await task.value
	}

	@Test("stores trusted contact tokens returned by issue response")
	func storesTrustedContactTokensReturnedByIssueResponse() async throws {
		let transport = MockProfileWebSocketTransport()
		let keys = InMemorySignalKeyStore(storage: [
			.tcToken: [
				"258840000000@s.whatsapp.net": try TrustedContactTokenCoding.encode(TrustedContactToken(
					token: Data(),
					timestamp: "1700000001",
					senderTimestamp: "1700000001"
				))
			]
		])
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: samplePrivacyTokenIssueCredentials(), keys: keys),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let task = Task {
			try await client.issuePrivacyTokens(
				for: ["258840000000@s.whatsapp.net"],
				timestamp: 1_700_000_001,
				requestID: "privacy-issue-store-1"
			)
		}
		_ = try await transport.waitForSentNode()

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "privacy-issue-store-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "tokens", content: .nodes([
					BinaryNode(
						tag: "token",
						attrs: ["type": "trusted_contact", "t": "1700000002"],
						content: .data(Data([0xab, 0xcd]))
					)
				]))
			])
		))
		_ = try await task.value

		let storedData = try #require(await keys.get(.tcToken, ids: ["258840000000@s.whatsapp.net"])["258840000000@s.whatsapp.net"])
		#expect(try TrustedContactTokenCoding.decode(storedData) == TrustedContactToken(
			token: Data([0xab, 0xcd]),
			timestamp: "1700000002",
			senderTimestamp: "1700000001"
		))
		let indexData = try #require(await keys.get(.tcToken, ids: [TrustedContactTokenCoding.indexKey])[TrustedContactTokenCoding.indexKey])
		#expect(try TrustedContactTokenCoding.decodeIndex(indexData) == ["258840000000@s.whatsapp.net"])
	}
}

private func samplePrivacyTokenIssueCredentials() -> AuthenticationCredentials {
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
