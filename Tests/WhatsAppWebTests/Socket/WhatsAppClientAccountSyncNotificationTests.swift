import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client account sync notifications")
struct WhatsAppClientAccountSyncNotificationTests {
	@Test("updates default disappearing mode credentials from account sync notifications")
	func updatesDefaultDisappearingModeCredentialsFromAccountSyncNotifications() async throws {
		let credentials = accountSyncCredentials()
		let state = AuthenticationState(credentials: credentials, keys: InMemorySignalKeyStore())
		let client = WhatsAppClient(authenticationState: state)
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "account-sync-1", "type": "account_sync"],
			content: .nodes([
				BinaryNode(tag: "disappearing_mode", attrs: ["duration": "86400", "t": "1700000000"])
			])
		))

		var updated = credentials
		updated.accountSettings.defaultDisappearingMode = AccountDisappearingModeSetting(
			ephemeralExpiration: 86_400,
			ephemeralSettingTimestamp: 1_700_000_000
		)
		#expect(await events.next() == .credentialsUpdated(updated))
		#expect(await client.authenticationState?.credentials == updated)
	}

	@Test("emits blocklist updates and acknowledges account sync notifications")
	func emitsBlocklistUpdatesAndAcknowledgesAccountSyncNotifications() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "account-sync-2", "type": "account_sync"],
			content: .nodes([
				BinaryNode(tag: "blocklist", content: .nodes([
					BinaryNode(tag: "item", attrs: ["jid": "123@s.whatsapp.net", "action": "block"]),
					BinaryNode(tag: "item", attrs: ["jid": "456@s.whatsapp.net", "action": "unblock"])
				]))
			])
		))

		#expect(await events.next() == .blocklistUpdated(BlocklistUpdate(
			jids: ["123@s.whatsapp.net"],
			type: .add
		)))
		#expect(await events.next() == .blocklistUpdated(BlocklistUpdate(
			jids: ["456@s.whatsapp.net"],
			type: .remove
		)))
		let ack = try await firstAccountSyncAck(from: transport)
		#expect(ack == BinaryNode(
			tag: "ack",
			attrs: ["id": "account-sync-2", "to": "@s.whatsapp.net", "class": "notification", "type": "account_sync"]
		))
	}
}

private func accountSyncCredentials() -> AuthenticationCredentials {
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

private func firstAccountSyncAck(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	let frame = try #require(await transport.sentFrames.first)
	var codec = NoiseFrameCodec()
	return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
}
