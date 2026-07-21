import Foundation
import Testing
import WhatsAppWeb

@Suite("Public client dependencies")
struct PublicClientDependencyTests {
	@Test("external consumers can construct a message-capable client")
	func externalConsumersCanConstructMessageCapableClient() async throws {
		let dependencies = WhatsAppClientMessageDependencies(
			messageEncryptor: PublicMessageEncryptor(),
			messageDeviceResolver: PublicDeviceResolver(),
			signalSessionPreparer: PublicSessionPreparer(),
			mediaUploader: PublicMediaUploader(),
			incomingSignalDecryptor: PublicSignalDecryptor(),
			preKeyUploader: PublicPreKeyUploader()
		)

		_ = WhatsAppClient(messageDependencies: dependencies)
	}

	@Test("Baileys assertSessions alias delegates to configured session preparer")
	func baileysAssertSessionsAliasDelegatesToConfiguredSessionPreparer() async throws {
		let preparer = PublicSessionPreparer()
		let dependencies = WhatsAppClientMessageDependencies(
			messageEncryptor: PublicMessageEncryptor(),
			messageDeviceResolver: PublicDeviceResolver(),
			signalSessionPreparer: preparer
		)
		let client = WhatsAppClient(messageDependencies: dependencies)

		let didFetch = try await client.assertSessions(
			for: ["123:0@s.whatsapp.net", "123:1@s.whatsapp.net"],
			force: true
		)

		#expect(didFetch)
	}

	@Test("Baileys assertSessions alias requires session preparer")
	func baileysAssertSessionsAliasRequiresSessionPreparer() async {
		let client = WhatsAppClient()

		await #expect(throws: WhatsAppClientError.missingSignalSessionPreparer) {
			try await client.assertSessions(for: ["123:0@s.whatsapp.net"])
		}
	}

	@Test("external consumers can provide pre-key upload through message dependencies")
	func externalConsumersCanProvidePreKeyUploadThroughMessageDependencies() async throws {
		let uploader = PublicPreKeyUploader()
		let dependencies = WhatsAppClientMessageDependencies(
			messageEncryptor: PublicMessageEncryptor(),
			messageDeviceResolver: PublicDeviceResolver(),
			signalSessionPreparer: PublicSessionPreparer(),
			preKeyUploader: uploader
		)
		let client = WhatsAppClient(messageDependencies: dependencies)
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "encrypt-public", "type": "encrypt"],
			content: .nodes([
				BinaryNode(tag: "count", attrs: ["value": "3"])
			])
		))

		#expect(await events.next() == .preKeyCountUpdated(PreKeyCountUpdate(
			count: 3,
			shouldUploadMorePreKeys: true
		)))
		#expect(await uploader.calls == [5])
	}

	@Test("external consumers can receive typed Signal pre-key upload requests")
	func externalConsumersCanReceiveTypedSignalPreKeyUploadRequests() async throws {
		let uploader = PublicSignalPreKeyUploader()
		let dependencies = WhatsAppClientMessageDependencies(
			messageEncryptor: PublicMessageEncryptor(),
			messageDeviceResolver: PublicDeviceResolver(),
			signalSessionPreparer: PublicSessionPreparer(),
			preKeyUploader: uploader
		)
		let client = WhatsAppClient(messageDependencies: dependencies)
		var events = client.events.makeAsyncIterator()

		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "encrypt-public-typed", "type": "encrypt"],
			content: .nodes([
				BinaryNode(tag: "count", attrs: ["value": "2"])
			])
		))

		#expect(await events.next() == .preKeyCountUpdated(PreKeyCountUpdate(
			count: 2,
			shouldUploadMorePreKeys: true
		)))
		#expect(await uploader.requests == [
			SignalPreKeyUploadRequest(currentCount: 2, requestedUploadCount: 5)
		])
	}

	@Test("external consumers can compose Signal session preparation")
	func externalConsumersCanComposeSignalSessionPreparation() async throws {
		let keys = InMemorySignalKeyStore()
		let resolver = PublicBundleResolver()
		let injector = PublicSessionInjector()
		let preparer = SignalSessionPreparer(
			keys: keys,
			bundleResolver: resolver,
			sessionInjector: injector
		)

		let prepared = try await preparer.assertSessions(for: ["123.0@s.whatsapp.net"], force: false)

		#expect(prepared)
		#expect(await injector.bundles.map(\.jid) == ["123.0@s.whatsapp.net"])
	}

	@Test("external consumers can compose Signal session preparation with address checker")
	func externalConsumersCanComposeSignalSessionPreparationWithAddressChecker() async throws {
		let checker = PublicSessionAddressChecker(existingAddresses: [
			SignalProtocolAddress(name: "123", deviceID: 0)
		])
		let resolver = PublicBundleResolver()
		let injector = PublicSessionInjector()
		let preparer = SignalSessionPreparer(
			addressChecker: checker,
			bundleResolver: resolver,
			sessionInjector: injector
		)

		let prepared = try await preparer.assertSessions(for: [
			"123@s.whatsapp.net",
			"123:1@s.whatsapp.net"
		])

		#expect(prepared)
		#expect(await checker.calls == [[
			SignalSessionAddressCheck(jid: "123@s.whatsapp.net", address: SignalProtocolAddress(name: "123", deviceID: 0)),
			SignalSessionAddressCheck(jid: "123:1@s.whatsapp.net", address: SignalProtocolAddress(name: "123", deviceID: 1))
		]])
		#expect(await injector.bundles.map(\.jid) == ["123:1@s.whatsapp.net"])
	}

	@Test("external consumers can validate Signal session bundle material")
	func externalConsumersCanValidateSignalSessionBundleMaterial() throws {
		let validBundle = SignalSessionBundle(
			jid: "123:0@s.whatsapp.net",
			registrationID: 1,
			identityKey: Data([5]) + Data(repeating: 1, count: 32),
			signedPreKey: SignalPreKey(
				keyID: 2,
				publicKey: Data([5]) + Data(repeating: 2, count: 32),
				signature: Data(repeating: 3, count: 64)
			),
			preKey: SignalPreKey(keyID: 3, publicKey: Data([5]) + Data(repeating: 4, count: 32))
		)
		let invalidBundle = SignalSessionBundle(
			jid: "123:0@s.whatsapp.net",
			registrationID: 1,
			identityKey: Data([5]) + Data(repeating: 1, count: 32),
			signedPreKey: SignalPreKey(
				keyID: 2,
				publicKey: Data([4]) + Data(repeating: 2, count: 32),
				signature: Data(repeating: 3, count: 64)
			),
			preKey: SignalPreKey(keyID: 3, publicKey: Data([5]) + Data(repeating: 4, count: 32))
		)

		#expect(validBundle.hasValidSignalKeyMaterial)
		#expect(!invalidBundle.hasValidSignalKeyMaterial)
		#expect(try validBundle.validatedAddress() == SignalProtocolAddress(name: "123", deviceID: 0))
		#expect(throws: SignalSessionBundleValidationError.invalidKeyMaterial) {
			try invalidBundle.validatedAddress()
		}
		#expect(throws: SignalSessionBundleValidationError.invalidAddress) {
			try SignalSessionBundle(
				jid: "invalid",
				registrationID: 1,
				identityKey: Data([5]) + Data(repeating: 1, count: 32),
				signedPreKey: SignalPreKey(
					keyID: 2,
					publicKey: Data([5]) + Data(repeating: 2, count: 32),
					signature: Data(repeating: 3, count: 64)
				),
				preKey: SignalPreKey(keyID: 3, publicKey: Data([5]) + Data(repeating: 4, count: 32))
			).validatedAddress()
		}
	}

	@Test("external consumers can parse Signal protocol addresses with typed failures")
	func externalConsumersCanParseSignalProtocolAddressesWithTypedFailures() throws {
		#expect(
			try SignalProtocolAddress.validated(jid: "123:4@c.us")
				== SignalProtocolAddress(name: "123", deviceID: 4)
		)
		#expect(throws: SignalProtocolAddressValidationError.invalidJID) {
			try SignalProtocolAddress.validated(jid: "not-a-jid")
		}
	}

	@Test("external consumers can build typed incoming Signal decryption requests")
	func externalConsumersCanBuildTypedIncomingSignalDecryptionRequests() async throws {
		let decryptor = PublicSignalDecryptor()
		let directRequest = try SignalDirectMessageDecryptionRequest(
			jid: "123:4@c.us",
			type: "msg",
			localJID: "999:0@s.whatsapp.net",
			ciphertext: Data([0xaa])
		)
		let preKeyRequest = try SignalDirectMessageDecryptionRequest(
			jid: "123:4@c.us",
			type: "pkmsg",
			ciphertext: Data([0xab])
		)
		let groupRequest = try SignalGroupMessageDecryptionRequest(
			groupJID: "111-222@g.us",
			authorJID: "123:4@s.whatsapp.net",
			ciphertext: Data([0xbb])
		)
		let distributionRequest = try SenderKeyDistributionMessageRequest(
			authorJID: "123:4@s.whatsapp.net",
			groupJID: "111-222@g.us",
			messageData: Data([0xcc])
		)

		#expect(directRequest.address == SignalProtocolAddress(name: "123", deviceID: 4))
		#expect(directRequest.localAddress == SignalProtocolAddress(name: "999", deviceID: 0))
		#expect(directRequest.ciphertextType == .signalMessage)
		#expect(preKeyRequest.ciphertextType == .preKeySignalMessage)
		#expect(groupRequest.groupJID == "111-222@g.us")
		#expect(groupRequest.authorAddress == SignalProtocolAddress(name: "123", deviceID: 4))
		#expect(distributionRequest.groupJID == "111-222@g.us")
		#expect(distributionRequest.authorAddress == SignalProtocolAddress(name: "123", deviceID: 4))
		#expect(try await decryptor.decryptMessage(directRequest) == Data([0xaa]))
		#expect(try await decryptor.decryptGroupMessage(groupRequest) == Data([0xbb]))
		try await decryptor.processSenderKeyDistributionMessage(distributionRequest)
		#expect(throws: SignalMessageDecryptionRequestValidationError.invalidGroupJID) {
			try SignalGroupMessageDecryptionRequest(
				groupJID: "123@s.whatsapp.net",
				authorJID: "123:4@s.whatsapp.net",
				ciphertext: Data([0xdd])
			)
		}
		#expect(throws: SignalMessageDecryptionRequestValidationError.unsupportedDirectCiphertextType("skmsg")) {
			try SignalDirectMessageDecryptionRequest(
				jid: "123:4@s.whatsapp.net",
				type: "skmsg",
				ciphertext: Data([0xdd])
			)
		}
		#expect(throws: SignalMessageDecryptionRequestValidationError.emptyCiphertext) {
			try SignalDirectMessageDecryptionRequest(
				jid: "123:4@s.whatsapp.net",
				type: "msg",
				ciphertext: Data()
			)
		}
		#expect(throws: SignalMessageDecryptionRequestValidationError.emptyCiphertext) {
			try SignalGroupMessageDecryptionRequest(
				groupJID: "111-222@g.us",
				authorJID: "123:4@s.whatsapp.net",
				ciphertext: Data()
			)
		}
		#expect(throws: SignalMessageDecryptionRequestValidationError.emptySenderKeyDistributionMessage) {
			try SenderKeyDistributionMessageRequest(
				authorJID: "123:4@s.whatsapp.net",
				messageData: Data()
			)
		}
	}

	@Test("external consumers can build typed outgoing Signal encryption requests")
	func externalConsumersCanBuildTypedOutgoingSignalEncryptionRequests() async throws {
		let encryptor = PublicMessageEncryptor()
		let directRequest = try SignalDirectMessageEncryptionRequest(
			jid: "123:4@c.us",
			localJID: "999:0@s.whatsapp.net",
			data: Data([0xaa])
		)
		let groupRequest = try SignalGroupMessageEncryptionRequest(
			groupJID: "111-222@g.us",
			senderJID: "123:4@s.whatsapp.net",
			data: Data([0xbb])
		)

		#expect(directRequest.address == SignalProtocolAddress(name: "123", deviceID: 4))
		#expect(directRequest.localAddress == SignalProtocolAddress(name: "999", deviceID: 0))
		#expect(groupRequest.groupJID == "111-222@g.us")
		#expect(groupRequest.senderAddress == SignalProtocolAddress(name: "123", deviceID: 4))
		#expect(try await encryptor.encryptMessage(directRequest) == EncryptedMessage(
			ciphertextType: .signalMessage,
			ciphertext: Data([0xaa])
		))
		#expect(throws: SignalMessageEncryptionRequestValidationError.invalidGroupJID) {
			try SignalGroupMessageEncryptionRequest(
				groupJID: "123@s.whatsapp.net",
				senderJID: "123:4@s.whatsapp.net",
				data: Data([0xcc])
			)
		}
		#expect(throws: SignalMessageEncryptionRequestValidationError.emptyMessageData) {
			try SignalDirectMessageEncryptionRequest(
				jid: "123:4@s.whatsapp.net",
				data: Data()
			)
		}
		#expect(throws: SignalMessageEncryptionRequestValidationError.emptyMessageData) {
			try SignalGroupMessageEncryptionRequest(
				groupJID: "111-222@g.us",
				senderJID: "123:4@s.whatsapp.net",
				data: Data()
			)
		}
	}

	@Test("external consumers can convert retry session bundles for Signal injection")
	func externalConsumersCanConvertRetrySessionBundlesForSignalInjection() throws {
		let retryBundle = MessageRetrySessionBundle(
			registrationID: 9,
			identityKey: Data([5]) + Data(repeating: 1, count: 32),
			signedPreKey: SignalPreKey(
				keyID: 2,
				publicKey: Data([5]) + Data(repeating: 2, count: 32),
				signature: Data(repeating: 3, count: 64)
			),
			preKey: SignalPreKey(keyID: 3, publicKey: Data([5]) + Data(repeating: 4, count: 32))
		)

		let sessionBundle = try retryBundle.signalSessionBundle(for: "123:2@s.whatsapp.net")
		let installRequest = try retryBundle.nativeInstallRequest(for: "123:2@s.whatsapp.net")

		#expect(sessionBundle.jid == "123:2@s.whatsapp.net")
		#expect(sessionBundle.registrationID == 9)
		#expect(try sessionBundle.validatedAddress() == SignalProtocolAddress(name: "123", deviceID: 2))
		#expect(installRequest == SignalSessionNativeInstallRequest(
			jid: "123:2@s.whatsapp.net",
			address: SignalProtocolAddress(name: "123", deviceID: 2),
			registrationID: 9,
			identityCurve25519PublicKey: Data(repeating: 1, count: 32),
			signedPreKeyID: 2,
			signedPreKeyCurve25519PublicKey: Data(repeating: 2, count: 32),
			signedPreKeySignature: Data(repeating: 3, count: 64),
			preKeyID: 3,
			preKeyCurve25519PublicKey: Data(repeating: 4, count: 32)
		))
		#expect(throws: MessageRetrySessionBundleValidationError.missingPreKey) {
			try MessageRetrySessionBundle(
				registrationID: 9,
				identityKey: retryBundle.identityKey,
				signedPreKey: retryBundle.signedPreKey
			).signalSessionBundle(for: "123:2@s.whatsapp.net")
		}
		#expect(throws: MessageRetrySessionBundleValidationError.invalidSessionBundle(.invalidAddress)) {
			try retryBundle.signalSessionBundle(for: "invalid")
		}
	}

	@Test("external consumers can wire default query backed message dependencies")
	func externalConsumersCanWireDefaultQueryBackedMessageDependencies() async throws {
		let keys = InMemorySignalKeyStore()
		let injector = PublicSessionInjector()
		let sessionChecker = PublicSessionChecker(existingJIDs: ["123:0@s.whatsapp.net"])
		let mediaTransport = PublicMediaUploadTransport(result: MediaUploadTransportResult(
			mediaURL: "https://media.example/uploaded",
			directPath: "/v/uploaded"
		))
		let dependencies = WhatsAppClientMessageDependencies(
			messageEncryptor: PublicMessageEncryptor(),
			signalKeys: keys,
			sessionInjector: injector,
			sessionChecker: sessionChecker,
			query: publicDependencyQuery,
			mediaUploader: WhatsAppMediaUploader(query: publicDependencyQuery, transport: mediaTransport),
			incomingSignalDecryptor: PublicSignalDecryptor()
		)

		let devices = try await dependencies.messageDeviceResolver.deviceJIDs(for: "123@s.whatsapp.net")
		let prepared = try await dependencies.signalSessionPreparer.assertSessions(for: devices, force: false)
		let upload = try await dependencies.mediaUploader?.upload(
			Data([1, 2, 3]),
			fileEncSha256Base64: "AB+//ZA==",
			mediaType: .image
		)

		#expect(devices == ["123:0@s.whatsapp.net", "123:1@s.whatsapp.net"])
		#expect(prepared)
		#expect(await sessionChecker.calls == [devices])
		#expect(await injector.bundles.map(\.jid) == ["123:1@s.whatsapp.net"])
		#expect(upload == MediaUploadResult(mediaURL: "https://media.example/uploaded", directPath: "/v/uploaded"))
		#expect(await mediaTransport.requests.map(\.url.absoluteString) == [
			"https://mmg.whatsapp.net/mms/image/AB-__ZA?auth=media-auth&token=AB-__ZA"
		])
	}

	@Test("external consumers can wire one Signal adapter")
	func externalConsumersCanWireOneSignalAdapter() async throws {
		let adapter = PublicSignalAdapter(existingJIDs: ["123:0@s.whatsapp.net"])
		let signalAdapter: any WhatsAppSignalAdapter = adapter
		let dependencies = WhatsAppClientMessageDependencies(
			signalAdapter: signalAdapter,
			query: publicDependencyQuery
		)

		let devices = try await dependencies.messageDeviceResolver.deviceJIDs(for: "123@s.whatsapp.net")
		let prepared = try await dependencies.signalSessionPreparer.assertSessions(for: devices, force: false)
		let encrypted = try await dependencies.messageEncryptor.encryptMessage(
			jid: "123:1@s.whatsapp.net",
			data: Data([0xaa])
		)
		let groupEncrypted = try await signalAdapter.encryptGroupMessage(
			group: "111-222@g.us",
			senderJID: "123@s.whatsapp.net",
			data: Data([0xbb])
		)

		#expect(prepared)
		#expect(encrypted == EncryptedMessage(type: "msg", ciphertext: Data([0xaa])))
		#expect(groupEncrypted == EncryptedGroupMessage(
			ciphertext: Data([0xbb]),
			senderKeyDistributionMessage: Data([0x11, 0x22])
		))
		#expect(await adapter.checkedJIDs == [devices])
		#expect(await adapter.injectedBundles.map(\.address) == [
			SignalProtocolAddress(name: "123", deviceID: 1)
		])
	}
}
