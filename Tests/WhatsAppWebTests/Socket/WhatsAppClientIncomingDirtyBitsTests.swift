import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client incoming dirty bits")
struct WhatsAppClientIncomingDirtyBitsTests {
	@Test("updates account sync timestamp and cleans the previous dirty window")
	func updatesAccountSyncTimestampAndCleansPreviousDirtyWindow() async throws {
		var credentials = dirtyBitsCredentials()
		credentials.lastAccountSyncTimestamp = 1_700_000_000
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: credentials, keys: InMemorySignalKeyStore()),
			transportFactory: { _ in transport }
		)
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "ib",
			content: .nodes([
				BinaryNode(tag: "dirty", attrs: ["type": "account_sync", "timestamp": "1700000300"])
			])
		))

		let clean = try await transport.waitForSentNode()
		#expect(clean.attrs["xmlns"] == "urn:xmpp:whatsapp:dirty")
		#expect(clean.firstChild(named: "clean")?.attrs["type"] == "account_sync")
		#expect(clean.firstChild(named: "clean")?.attrs["timestamp"] == "1700000000")

		credentials.lastAccountSyncTimestamp = 1_700_000_300
		#expect(await events.next() == .credentialsUpdated(credentials))
		#expect(await client.authenticationState?.credentials.lastAccountSyncTimestamp == 1_700_000_300)
	}

	@Test("refreshes participating groups before cleaning group dirty bits")
	func refreshesParticipatingGroupsBeforeCleaningGroupDirtyBits() async throws {
		let transport = MockGroupWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			await client.handleIncomingNode(BinaryNode(
				tag: "ib",
				content: .nodes([BinaryNode(tag: "dirty", attrs: ["type": "groups"])])
			))
		}

		let groupRequest = try await transport.waitForSentNode(at: 0)
		#expect(groupRequest.attrs["to"] == "@g.us")
		#expect(groupRequest.attrs["type"] == "get")
		#expect(groupRequest.firstChild(named: "participating") != nil)
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": groupRequest.attrs["id"] ?? "", "type": "result"],
			content: .nodes([BinaryNode(tag: "groups")])
		))

		await task.value
		let cleanRequest = try await transport.waitForSentNode(at: 1)
		#expect(cleanRequest.attrs["xmlns"] == "urn:xmpp:whatsapp:dirty")
		#expect(cleanRequest.firstChild(named: "clean")?.attrs["type"] == "groups")
	}

	@Test("refreshes participating communities before cleaning group dirty bits")
	func refreshesParticipatingCommunitiesBeforeCleaningGroupDirtyBits() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			await client.handleIncomingNode(BinaryNode(
				tag: "ib",
				content: .nodes([BinaryNode(tag: "dirty", attrs: ["type": "communities"])])
			))
		}

		let communityRequest = try await transport.waitForSentNode(at: 0)
		#expect(communityRequest.attrs["to"] == "@g.us")
		#expect(communityRequest.attrs["type"] == "get")
		#expect(communityRequest.firstChild(named: "participating") != nil)
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": communityRequest.attrs["id"] ?? "", "type": "result"],
			content: .nodes([BinaryNode(tag: "communities")])
		))

		await task.value
		let cleanRequest = try await transport.waitForSentNode(at: 1)
		#expect(cleanRequest.attrs["xmlns"] == "urn:xmpp:whatsapp:dirty")
		#expect(cleanRequest.firstChild(named: "clean")?.attrs["type"] == "groups")
	}
}

private func dirtyBitsCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
		signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data([6])),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([8])),
			signature: Data([9]),
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
