import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client AB props")
struct WhatsAppClientABPropsTests {
	@Test("profile picture privacy token prop disables token attachment")
	func profilePicturePrivacyTokenPropDisablesTokenAttachment() async throws {
		let transport = MockProfileWebSocketTransport()
		let keys = InMemorySignalKeyStore(storage: [
			.tcToken: [
				"123@s.whatsapp.net": try TrustedContactTokenCoding.encode(TrustedContactToken(
					token: Data([0xca, 0xfe]),
					timestamp: "9999999999"
				))
			]
		])
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: abPropsCredentials(), keys: keys),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let propsTask = Task {
			try await client.fetchProps(requestID: "props-disable-profile-token")
		}
		_ = try await transport.waitForSentNode(at: 0)
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "props-disable-profile-token", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "props", content: .nodes([
					BinaryNode(tag: "prop", attrs: ["config_code": "9666", "config_value": "false"])
				]))
			])
		))
		#expect(try await propsTask.value == ["9666": "false"])

		let pictureTask = Task {
			try await client.profilePictureURL(for: "123@s.whatsapp.net", requestID: "picture-after-props")
		}
		let pictureRequest = try await transport.waitForSentNode(at: 1)
		#expect(pictureRequest.content == .nodes([
			BinaryNode(tag: "picture", attrs: ["type": "preview", "query": "url"])
		]))

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "picture-after-props", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "picture", attrs: ["url": "https://mmg.whatsapp.net/profile.jpg"])
			])
		))
		#expect(try await pictureTask.value == "https://mmg.whatsapp.net/profile.jpg")
	}

	@Test("one-to-one privacy token prop disables message token attachment")
	func oneToOnePrivacyTokenPropDisablesMessageTokenAttachment() async throws {
		let transport = MockProfileWebSocketTransport()
		let keys = InMemorySignalKeyStore(storage: [
			.tcToken: [
				"123@s.whatsapp.net": try TrustedContactTokenCoding.encode(TrustedContactToken(
					token: Data([0xaa, 0xbb]),
					timestamp: "9999999999"
				))
			]
		])
		let callOrder = MessageSendCallOrder()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: abPropsCredentials(), keys: keys),
			transportFactory: { _ in transport },
			messageEncryptor: StubMessageSendEncryptor(
				results: [EncryptedMessage(type: "msg", ciphertext: Data([0x10]))],
				callOrder: callOrder
			),
			messageDeviceResolver: StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"]),
			signalSessionPreparer: StubSignalSessionPreparer(callOrder: callOrder),
			messageEncoder: MessageEncoder(randomByte: { 0x00 })
		)
		try await client.connect()

		let propsTask = Task {
			try await client.fetchProps(requestID: "props-disable-message-token")
		}
		_ = try await transport.waitForSentNode(at: 0)
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "props-disable-message-token", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "props", content: .nodes([
					BinaryNode(tag: "prop", attrs: ["name": "10518", "value": "false"])
				]))
			])
		))
		#expect(try await propsTask.value == ["10518": "false"])

		_ = try await client.sendTextMessage(to: "123@s.whatsapp.net", text: "hello", messageID: "3EB0ABPROPS")

		let stanza = try await transport.waitForSentNode(at: 1)
		#expect(stanza.firstChild(named: "tctoken") == nil)
	}
}

private func abPropsCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
		signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data([6])),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([8])),
			signature: Data([9]),
			keyID: 1
		),
		registrationID: 559,
		advSecretKey: "adv-secret",
		me: WhatsAppUser(id: "999@s.whatsapp.net", name: "Swift User", lid: "999@lid"),
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true
	)
}
