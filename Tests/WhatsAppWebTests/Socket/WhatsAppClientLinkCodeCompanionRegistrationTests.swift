import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client link-code companion registration notifications")
struct WhatsAppClientLinkCodeCompanionRegistrationTests {
	@Test("finishes link-code companion registration and stores the derived app-state secret")
	func finishesLinkCodeCompanionRegistration() async throws {
		let transport = MockProfileWebSocketTransport()
		let credentials = try sampleLinkCodeCredentials()
		let messageIDGenerator = MessageIDGenerator(
			unixTimestampSeconds: { 1 },
			randomBytes: { Data(repeating: 0x44, count: $0) }
		)
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: credentials, keys: InMemorySignalKeyStore()),
			transportFactory: { _ in transport },
			messageIDGenerator: messageIDGenerator,
			linkCodeCompanionRegistrationProcessor: DefaultLinkCodeCompanionRegistrationProcessor(
				randomBytes: deterministicRegistrationRandomBytes()
			)
		)
		var events = client.events.makeAsyncIterator()
		try await client.connect()

		let primaryEphemeralPrivateKey = Data(repeating: 9, count: 32)
		let primaryEphemeralPublicKey = try NoiseCurve25519.publicKey(privateKey: primaryEphemeralPrivateKey)
		let wrappedPrimaryEphemeral = try PairingCode.wrapCompanionEphemeralPublicKey(
			primaryEphemeralPublicKey,
			pairingCode: "ABCDEFGH",
			salt: Data(1...32),
			iv: Data(33...48)
		)
		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["id": "notif-1", "from": "@s.whatsapp.net", "type": "link_code_companion_reg"],
			content: .nodes([
				BinaryNode(
					tag: "link_code_companion_reg",
					content: .nodes([
						BinaryNode(tag: "link_code_pairing_ref", content: .data(Data("pair-ref".utf8))),
						BinaryNode(
							tag: "primary_identity_pub",
							content: .data(try NoiseCurve25519.publicKey(privateKey: Data(repeating: 8, count: 32)))
						),
						BinaryNode(
							tag: "link_code_pairing_wrapped_primary_ephemeral_pub",
							content: .data(wrappedPrimaryEphemeral)
						)
					])
				)
			])
		))

		let updatedCredentials = try #require(await client.authenticationState?.credentials)
		#expect(updatedCredentials.registered)
		#expect(updatedCredentials.advSecretKey == "+8h1+VCNWpM56FfrWg3lc+eJAl+CVrPGgeKvlrgFNdg=")
		#expect(await events.next() == .credentialsUpdated(updatedCredentials))

		let reply = try await transport.waitForSentNode()
		#expect(reply.attrs["to"] == "@s.whatsapp.net")
		#expect(reply.attrs["type"] == "set")
		#expect(reply.attrs["xmlns"] == "md")
		let expectedRequestID = try messageIDGenerator.generateV2(userID: credentials.me?.id)
		#expect(reply.attrs["id"] == expectedRequestID)
		let registration = try #require(reply.firstChild(named: "link_code_companion_reg"))
		#expect(registration.attrs["jid"] == "258840000000@s.whatsapp.net")
		#expect(registration.attrs["stage"] == "companion_finish")
		#expect(registration.firstChild(named: "companion_identity_public")?.content == .data(credentials.signedIdentityKey.publicKey))
		#expect(registration.firstChild(named: "link_code_pairing_ref")?.content == .data(Data("pair-ref".utf8)))
		let bundle = try #require(registration.childData(named: "link_code_pairing_wrapped_key_bundle"))
		#expect(bundle.count == 156)
		#expect(bundle.prefix(32) == Data(repeating: 0xbb, count: 32))
		#expect(Data(bundle.dropFirst(32).prefix(12)) == Data(repeating: 0xcc, count: 12))

		let ack = try await transport.waitForSentNode(at: 1)
		#expect(ack.tag == "ack")
		#expect(ack.attrs["id"] == "notif-1")
		#expect(ack.attrs["class"] == "notification")
		#expect(ack.attrs["type"] == "link_code_companion_reg")
	}
}

private func deterministicRegistrationRandomBytes() -> @Sendable (Int) throws -> Data {
	let sequence = RandomByteSequence()
	return { count in
		switch sequence.nextCall() {
		case 1:
			return Data(repeating: 0xaa, count: count)
		case 2:
			return Data(repeating: 0xbb, count: count)
		default:
			return Data(repeating: 0xcc, count: count)
		}
	}
}

private final class RandomByteSequence: @unchecked Sendable {
	private let lock = NSLock()
	private var calls = 0

	func nextCall() -> Int {
		lock.lock()
		defer { lock.unlock() }
		calls += 1
		return calls
	}
}

private func sampleLinkCodeCredentials() throws -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(
			privateKey: Data(repeating: 1, count: 32),
			publicKey: try NoiseCurve25519.publicKey(privateKey: Data(repeating: 1, count: 32))
		),
		pairingEphemeralKeyPair: AuthenticationKeyPair(
			privateKey: Data(repeating: 2, count: 32),
			publicKey: try NoiseCurve25519.publicKey(privateKey: Data(repeating: 2, count: 32))
		),
		signedIdentityKey: AuthenticationKeyPair(
			privateKey: Data(repeating: 3, count: 32),
			publicKey: try NoiseCurve25519.publicKey(privateKey: Data(repeating: 3, count: 32))
		),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(
				privateKey: Data(repeating: 5, count: 32),
				publicKey: try NoiseCurve25519.publicKey(privateKey: Data(repeating: 5, count: 32))
			),
			signature: Data(repeating: 7, count: 64),
			keyID: 1
		),
		registrationID: 559,
		advSecretKey: "adv-secret",
		me: WhatsAppUser(id: "258840000000@s.whatsapp.net", name: "~"),
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: false,
		pairingCode: "ABCDEFGH"
	)
}
