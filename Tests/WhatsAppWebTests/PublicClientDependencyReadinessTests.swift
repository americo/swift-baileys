import Foundation
import Testing
import WhatsAppWeb

@Suite("Public client dependency readiness")
struct PublicClientDependencyReadinessTests {
	@Test("external consumers can inspect missing message dependencies")
	func externalConsumersCanInspectMissingMessageDependencies() async throws {
		let client = WhatsAppClient()

		#expect(await client.missingMessageDependencies() == [
			.directSend: [
				.messageEncryptor,
				.messageDeviceResolver,
				.signalSessionPreparer
			],
			.groupSend: [
				.messageEncryptor,
				.groupMessageEncryptor,
				.messageDeviceResolver,
				.signalSessionPreparer
			],
			.mediaSend: [
				.messageEncryptor,
				.messageDeviceResolver,
				.signalSessionPreparer,
				.mediaUploader
			],
			.incomingDecrypt: [.incomingSignalDecryptor],
			.preKeyUpload: [.preKeyUploaderOrAuthenticationState],
			.retryResend: [
				.messageEncryptor,
				.messageDeviceResolver,
				.signalSessionPreparer
			]
		])
		#expect(await client.missingMessageDependencies(for: .directSend) == [
			.messageEncryptor,
			.messageDeviceResolver,
			.signalSessionPreparer
		])
		#expect(await client.missingMessageDependencies(for: .groupSend) == [
			.messageEncryptor,
			.groupMessageEncryptor,
			.messageDeviceResolver,
			.signalSessionPreparer
		])
		#expect(await client.missingMessageDependencies(for: .mediaSend) == [
			.messageEncryptor,
			.messageDeviceResolver,
			.signalSessionPreparer,
			.mediaUploader
		])
		#expect(await client.missingMessageDependencies(for: .incomingDecrypt) == [.incomingSignalDecryptor])
		#expect(await client.missingMessageDependencies(for: .preKeyUpload) == [.preKeyUploaderOrAuthenticationState])
		#expect(await client.missingMessageDependencies(for: .retryResend) == [
			.messageEncryptor,
			.messageDeviceResolver,
			.signalSessionPreparer
		])
	}

	@Test("external consumers can verify configured message dependencies")
	func externalConsumersCanVerifyConfiguredMessageDependencies() async throws {
		let authState = AuthenticationState(credentials: sampleCredentials(), keys: InMemorySignalKeyStore())
		let dependencies = WhatsAppClientMessageDependencies(
			messageEncryptor: ReadinessMessageAdapter(),
			groupMessageEncryptor: ReadinessMessageAdapter(),
			messageDeviceResolver: ReadinessDeviceResolver(),
			signalSessionPreparer: ReadinessSessionPreparer(),
			mediaUploader: ReadinessMediaUploader(),
			incomingSignalDecryptor: ReadinessSignalDecryptor()
		)
		let client = WhatsAppClient(authenticationState: authState, messageDependencies: dependencies)

		for capability in WhatsAppClientMessageCapability.allCases {
			#expect(await client.missingMessageDependencies(for: capability).isEmpty)
		}
		#expect(await client.missingMessageDependencies().isEmpty)
	}

	@Test("external consumers can assert required message capabilities")
	func externalConsumersCanAssertRequiredMessageCapabilities() async throws {
		let client = WhatsAppClient()

		await #expect(throws: WhatsAppClientMessageDependencyError(missingByCapability: [
			.directSend: [
				.messageEncryptor,
				.messageDeviceResolver,
				.signalSessionPreparer
			],
			.incomingDecrypt: [.incomingSignalDecryptor]
		])) {
			try await client.assertMessageCapabilities([.directSend, .incomingDecrypt])
		}
	}

	@Test("external consumers can assert all message capabilities after configuration")
	func externalConsumersCanAssertAllMessageCapabilitiesAfterConfiguration() async throws {
		let authState = AuthenticationState(credentials: sampleCredentials(), keys: InMemorySignalKeyStore())
		let dependencies = WhatsAppClientMessageDependencies(
			messageEncryptor: ReadinessMessageAdapter(),
			groupMessageEncryptor: ReadinessMessageAdapter(),
			messageDeviceResolver: ReadinessDeviceResolver(),
			signalSessionPreparer: ReadinessSessionPreparer(),
			mediaUploader: ReadinessMediaUploader(),
			incomingSignalDecryptor: ReadinessSignalDecryptor()
		)
		let client = WhatsAppClient(authenticationState: authState, messageDependencies: dependencies)

		try await client.assertMessageCapabilities()
	}

	@Test("external consumers can inspect available message capabilities")
	func externalConsumersCanInspectAvailableMessageCapabilities() async throws {
		let client = WhatsAppClient()
		let adapter = PublicNativeSignalAdapter(existingAddresses: [])

		await client.configureNativeSignalAdapter(adapter, query: { _, _ in
			BinaryNode(tag: "iq", attrs: ["type": "result"])
		})

		#expect(await client.availableMessageCapabilities() == [
			.directSend,
			.groupSend,
			.incomingDecrypt,
			.preKeyUpload,
			.retryResend
		])

		await client.configureNativeSignalAdapter(adapter, query: { _, _ in
			BinaryNode(tag: "iq", attrs: ["type": "result"])
		}, mediaUploader: ReadinessMediaUploader())

		#expect(await client.availableMessageCapabilities() == Set(WhatsAppClientMessageCapability.allCases))
	}
}

private actor ReadinessMessageAdapter: MessageEncrypting, GroupMessageEncrypting {
	func encryptMessage(jid: String, data: Data) async throws -> EncryptedMessage {
		EncryptedMessage(type: "msg", ciphertext: data)
	}

	func encryptGroupMessage(group: String, senderJID: String, data: Data) async throws -> EncryptedGroupMessage {
		EncryptedGroupMessage(ciphertext: data, senderKeyDistributionMessage: Data([1]))
	}
}

private struct ReadinessDeviceResolver: MessageDeviceResolving {
	func deviceJIDs(for jid: String) async throws -> [String] {
		[jid]
	}
}

private struct ReadinessSessionPreparer: SignalSessionPreparing {
	func assertSessions(for jids: [String], force: Bool) async throws -> Bool {
		!jids.isEmpty
	}
}

private struct ReadinessMediaUploader: WhatsAppMediaUploading {
	func upload(_ data: Data, fileEncSha256Base64: String, mediaType: MediaType) async throws -> MediaUploadResult {
		MediaUploadResult(mediaURL: "https://media.example/file", directPath: "/file")
	}
}

private struct ReadinessSignalDecryptor: SignalMessageDecrypting {
	func decryptMessage(jid: String, type: String, ciphertext: Data) async throws -> Data {
		ciphertext
	}

	func decryptGroupMessage(group: String, authorJID: String, ciphertext: Data) async throws -> Data {
		ciphertext
	}

	func processSenderKeyDistributionMessage(authorJID: String, messageData: Data) async throws {}
}

private func sampleCredentials() -> AuthenticationCredentials {
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
		advSecretKey: "adv",
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true
	)
}
