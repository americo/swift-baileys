import Foundation
import Testing
import WhatsAppWeb

@Suite("Public native Signal incoming dependencies")
struct PublicNativeSignalIncomingDependencyTests {
	@Test("native Signal adapter drives client incoming decrypt path")
	func nativeSignalAdapterDrivesClientIncomingDecryptPath() async throws {
		let transport = PublicNativeSignalTransport()
		let adapter = PublicNativeSignalAdapter(existingAddresses: [])
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: AuthenticationCredentials(
					noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
					pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
					signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data([6])),
					signedPreKey: SignedAuthenticationKeyPair(
						keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([8])),
						signature: Data([9]),
						keyID: 10
					),
					registrationID: 11,
					advSecretKey: "secret",
					me: WhatsAppUser(id: "999:0@s.whatsapp.net"),
					nextPreKeyID: 12,
					firstUnuploadedPreKeyID: 13,
					accountSyncCounter: 0,
					registered: true
				),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		let plaintext = try publicNativeEncodedText("hello from native decrypt")
		var events = client.events.makeAsyncIterator()

		await client.configureNativeSignalAdapter(
			adapter,
			query: publicNativeDependencyQuery
		)
		try await client.connect()
		await transport.enqueueIncoming(BinaryNode(
			tag: "message",
			attrs: [
				"id": "incoming-native",
				"from": "123:1@s.whatsapp.net"
			],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "msg"], content: .data(plaintext))
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "incoming-native",
			from: "123@s.whatsapp.net",
			timestamp: nil,
			content: .text("hello from native decrypt")
		)))
		#expect(await adapter.directDecryptionRequests.map(\.address) == [
			SignalProtocolAddress(name: "123", deviceID: 1)
		])
		#expect(await adapter.directDecryptionRequests.map(\.localAddress) == [
			SignalProtocolAddress(name: "999", deviceID: 0)
		])
	}

	@Test("native Signal adapter drives client incoming group decrypt path")
	func nativeSignalAdapterDrivesClientIncomingGroupDecryptPath() async throws {
		let transport = PublicNativeSignalTransport()
		let adapter = PublicNativeSignalAdapter(existingAddresses: [])
		let client = WhatsAppClient(transportFactory: { _ in transport })
		let plaintext = try publicNativeEncodedText("hello from native group decrypt")
		var events = client.events.makeAsyncIterator()

		await client.configureNativeSignalAdapter(
			adapter,
			query: publicNativeDependencyQuery
		)
		try await client.connect()
		await transport.enqueueIncoming(BinaryNode(
			tag: "message",
			attrs: [
				"id": "incoming-native-group",
				"from": "111-222@g.us",
				"participant": "123:1@s.whatsapp.net"
			],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "skmsg"], content: .data(plaintext))
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "incoming-native-group",
			from: "111-222@g.us",
			timestamp: nil,
			content: .text("hello from native group decrypt"),
			participant: "123@s.whatsapp.net"
		)))
		#expect(await adapter.groupDecryptionRequests.map(\.authorAddress) == [
			SignalProtocolAddress(name: "123", deviceID: 1)
		])
		#expect(await adapter.groupDecryptionRequests.map(\.groupJID) == ["111-222@g.us"])
	}

	@Test("native Signal adapter imports sender key distribution from incoming messages")
	func nativeSignalAdapterImportsSenderKeyDistributionFromIncomingMessages() async throws {
		let transport = PublicNativeSignalTransport()
		let adapter = PublicNativeSignalAdapter(existingAddresses: [])
		let client = WhatsAppClient(transportFactory: { _ in transport })
		let distribution = publicNativeSenderKeyDistribution(
			groupID: "111-222@g.us",
			senderKey: Data([0xaa, 0xbb])
		)
		let plaintext = try publicNativeEncodedText(
			"hello with native sender key",
			senderKeyDistribution: distribution
		)
		var events = client.events.makeAsyncIterator()

		await client.configureNativeSignalAdapter(
			adapter,
			query: publicNativeDependencyQuery
		)
		try await client.connect()
		await transport.enqueueIncoming(BinaryNode(
			tag: "message",
			attrs: [
				"id": "incoming-native-skdm",
				"from": "111-222@g.us",
				"participant": "123:1@s.whatsapp.net"
			],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "skmsg"], content: .data(plaintext))
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "incoming-native-skdm",
			from: "111-222@g.us",
			timestamp: nil,
			content: .text("hello with native sender key"),
			participant: "123@s.whatsapp.net"
		)))
		#expect(await adapter.senderKeyDistributionRequests == [
			try SenderKeyDistributionMessageRequest(
				authorJID: "123:1@s.whatsapp.net",
				groupJID: "111-222@g.us",
				senderKeyDistributionData: Data([0xaa, 0xbb]),
				messageData: distribution
			)
		])
	}

	@Test("native Signal adapter imports fast ratchet sender key distribution from incoming messages")
	func nativeSignalAdapterImportsFastRatchetSenderKeyDistributionFromIncomingMessages() async throws {
		let transport = PublicNativeSignalTransport()
		let adapter = PublicNativeSignalAdapter(existingAddresses: [])
		let client = WhatsAppClient(transportFactory: { _ in transport })
		let distribution = publicNativeSenderKeyDistribution(
			groupID: "111-222@g.us",
			senderKey: Data([0xcc, 0xdd])
		)
		let plaintext = try publicNativeEncodedText(
			"hello with native fast ratchet sender key",
			senderKeyDistribution: distribution,
			senderKeyDistributionFieldTag: 0x7a
		)
		var events = client.events.makeAsyncIterator()

		await client.configureNativeSignalAdapter(
			adapter,
			query: publicNativeDependencyQuery
		)
		try await client.connect()
		await transport.enqueueIncoming(BinaryNode(
			tag: "message",
			attrs: [
				"id": "incoming-native-fast-ratchet-skdm",
				"from": "111-222@g.us",
				"participant": "123:1@s.whatsapp.net"
			],
			content: .nodes([
				BinaryNode(tag: "enc", attrs: ["type": "skmsg"], content: .data(plaintext))
			])
		))

		#expect(await events.next() == .receivedMessage(ReceivedMessage(
			id: "incoming-native-fast-ratchet-skdm",
			from: "111-222@g.us",
			timestamp: nil,
			content: .text("hello with native fast ratchet sender key"),
			participant: "123@s.whatsapp.net"
		)))
		#expect(await adapter.senderKeyDistributionRequests == [
			try SenderKeyDistributionMessageRequest(
				authorJID: "123:1@s.whatsapp.net",
				groupJID: "111-222@g.us",
				senderKeyDistributionData: Data([0xcc, 0xdd]),
				messageData: distribution
			)
		])
	}
}
