import Foundation
import Testing
import WhatsAppWeb

@Suite("Public native Signal adapter retry")
struct PublicNativeSignalAdapterRetryTests {
	@Test("native Signal adapter injects retry session bundle before cached resend")
	func nativeSignalAdapterInjectsRetrySessionBundleBeforeCachedResend() async throws {
		let transport = PublicNativeSignalTransport(respondsToQueries: true)
		let adapter = PublicNativeSignalAdapter(existingAddresses: [
			SignalProtocolAddress(name: "123", deviceID: 0)
		])
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
				keys: InMemorySignalKeyStore(storage: [
					.tcToken: [
						"123@s.whatsapp.net": try TrustedContactTokenCoding.encode(TrustedContactToken(
							token: Data(),
							timestamp: "9999999999",
							senderTimestamp: String(Int(Date().timeIntervalSince1970))
						))
					]
				])
			),
			transportFactory: { _ in transport }
		)
		var events = client.events.makeAsyncIterator()

		await client.configureNativeSignalAdapter(adapter)
		try await client.connect()
		_ = try await client.sendTextMessage(
			to: "123@s.whatsapp.net",
			text: "cached through native adapter",
			messageID: "3EB0NATIVERETRY"
		)

		await transport.enqueueIncoming(BinaryNode(
			tag: "receipt",
			attrs: [
				"from": "123@s.whatsapp.net",
				"id": "3EB0NATIVERETRY",
				"participant": "123:2@s.whatsapp.net",
				"type": "retry"
			],
			content: .nodes([
				BinaryNode(tag: "retry", attrs: ["count": "3"]),
				BinaryNode(tag: "registration", content: .data(Data([0, 0, 0, 9]))),
				publicNativeRetryKeysNode()
			])
		))

		#expect(await events.next() == .messageRetryRequested(MessageRetryRequest(
			key: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: true,
				id: "3EB0NATIVERETRY",
				participant: "123:2@s.whatsapp.net"
			),
			messageIDs: ["3EB0NATIVERETRY"],
			requesterJID: "123:2@s.whatsapp.net",
			retryCount: 3,
			requesterRegistrationID: 9,
			sessionBundle: publicNativeRetrySessionBundle()
		)))
		let sentNodes = await publicNativeWaitForSentNodes(5, in: transport)
		#expect(await adapter.installedRequests.map(\.address) == [
			SignalProtocolAddress(name: "123", deviceID: 1),
			SignalProtocolAddress(name: "123", deviceID: 2)
		])
		#expect(await adapter.installedRequests.map(\.localAddress) == [
			SignalProtocolAddress(name: "999", deviceID: 0),
			SignalProtocolAddress(name: "999", deviceID: 0)
		])
		#expect(await adapter.directEncryptionRequests.map(\.address) == [
			SignalProtocolAddress(name: "123", deviceID: 0),
			SignalProtocolAddress(name: "123", deviceID: 1),
			SignalProtocolAddress(name: "123", deviceID: 2)
		])
		#expect(sentNodes.map(\.tag) == ["iq", "iq", "message", "ack", "message"])
		#expect(sentNodes.last?.attrs["to"] == "123:2@s.whatsapp.net")
		#expect(sentNodes.last?.firstChild(named: "enc")?.attrs["count"] == "3")
	}

	@Test("retry session bundles expose local addresses for native installs")
	func retrySessionBundlesExposeLocalAddressesForNativeInstalls() throws {
		let request = try publicNativeRetrySessionBundle().nativeInstallRequest(
			for: "123:2@s.whatsapp.net",
			localJID: "999:0@s.whatsapp.net"
		)

		#expect(request.address == SignalProtocolAddress(name: "123", deviceID: 2))
		#expect(request.localAddress == SignalProtocolAddress(name: "999", deviceID: 0))
	}
}

private func publicNativeRetryKeysNode() -> BinaryNode {
	BinaryNode(
		tag: "keys",
		content: .nodes([
			BinaryNode(tag: "type", content: .data(Data([0x05]))),
			BinaryNode(tag: "identity", content: .data(Data(repeating: 0x11, count: 32))),
			publicNativeRetryPreKeyNode(
				tag: "skey",
				id: 8,
				value: 0x33,
				signature: Data(repeating: 0x44, count: 64)
			),
			publicNativeRetryPreKeyNode(tag: "key", id: 7, value: 0x22)
		])
	)
}

private func publicNativeRetryPreKeyNode(
	tag: String,
	id: Int,
	value: UInt8,
	signature: Data? = nil
) -> BinaryNode {
	var children = [
		BinaryNode(tag: "id", content: .data(Data([0, 0, UInt8(id)]))),
		BinaryNode(tag: "value", content: .data(Data(repeating: value, count: 32)))
	]
	if let signature {
		children.append(BinaryNode(tag: "signature", content: .data(signature)))
	}
	return BinaryNode(tag: tag, content: .nodes(children))
}

private func publicNativeRetrySessionBundle() -> MessageRetrySessionBundle {
	MessageRetrySessionBundle(
		registrationID: 9,
		identityKey: Data([0x05]) + Data(repeating: 0x11, count: 32),
		signedPreKey: SignalPreKey(
			keyID: 8,
			publicKey: Data([0x05]) + Data(repeating: 0x33, count: 32),
			signature: Data(repeating: 0x44, count: 64)
		),
		preKey: SignalPreKey(
			keyID: 7,
			publicKey: Data([0x05]) + Data(repeating: 0x22, count: 32)
		)
	)
}
