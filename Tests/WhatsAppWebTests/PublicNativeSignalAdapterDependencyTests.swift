import Foundation
import Testing
import WhatsAppWeb

@Suite("Public native Signal adapter dependencies")
struct PublicNativeSignalAdapterDependencyTests {
	@Test("external consumers can wire one native Signal adapter")
	func externalConsumersCanWireOneNativeSignalAdapter() async throws {
		let adapter = PublicNativeSignalAdapter(existingAddresses: [
			SignalProtocolAddress(name: "123", deviceID: 0)
		])
		let signalAdapter: any WhatsAppNativeSignalAdapter = adapter
		let dependencies = WhatsAppClientMessageDependencies(
			nativeSignalAdapter: signalAdapter,
			query: publicNativeDependencyQuery
		)

		let devices = try await dependencies.messageDeviceResolver.deviceJIDs(for: "123@s.whatsapp.net")
		let prepared = try await dependencies.signalSessionPreparer.assertSessions(for: devices, force: false)
		let encrypted = try await dependencies.messageEncryptor.encryptMessage(
			jid: "123:1@s.whatsapp.net",
			data: Data([0xaa])
		)
		let groupEncrypted = try await dependencies.groupMessageEncryptor?.encryptGroupMessage(
			group: "111-222@g.us",
			senderJID: "123:0@s.whatsapp.net",
			data: Data([0xbb])
		)
		let decrypted = try await dependencies.incomingSignalDecryptor?.decryptMessage(
			jid: "123:1@s.whatsapp.net",
			type: "msg",
			ciphertext: Data([0xcc])
		)
		try await dependencies.preKeyUploader?.uploadPreKeys(count: 5)

		#expect(prepared)
		#expect(encrypted == EncryptedMessage(type: "msg", ciphertext: Data([0xaa])))
		#expect(groupEncrypted == EncryptedGroupMessage(
			ciphertext: Data([0xbb]),
			senderKeyDistributionMessage: Data([0x11, 0x22])
		))
		#expect(decrypted == Data([0xcc]))
		#expect(await adapter.directEncryptionRequests.map(\.address) == [
			SignalProtocolAddress(name: "123", deviceID: 1)
		])
		#expect(await adapter.groupEncryptionRequests.map(\.senderAddress) == [
			SignalProtocolAddress(name: "123", deviceID: 0)
		])
		#expect(await adapter.directDecryptionRequests.map(\.address) == [
			SignalProtocolAddress(name: "123", deviceID: 1)
		])
		#expect(await adapter.checkedAddresses == [[
			SignalSessionAddressCheck(jid: "123:0@s.whatsapp.net", address: SignalProtocolAddress(name: "123", deviceID: 0)),
			SignalSessionAddressCheck(jid: "123:1@s.whatsapp.net", address: SignalProtocolAddress(name: "123", deviceID: 1))
		]])
		#expect(await adapter.installedRequests.map(\.address) == [
			SignalProtocolAddress(name: "123", deviceID: 1)
		])
		#expect(await adapter.preKeyUploadRequests == [
			SignalPreKeyUploadRequest(requestedUploadCount: 5)
		])
	}

	@Test("native Signal adapter signs authentication signed pre-keys")
	func nativeSignalAdapterSignsAuthenticationSignedPreKeys() throws {
		let adapter = PublicNativeSignalAdapter(existingAddresses: [])
		let signer: any SignalSignedPreKeySigning = adapter
		let factory = AuthenticationCredentialsFactory(
			keyPairGenerator: PublicNativeAuthenticationKeyPairSequence([
				AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32)),
				AuthenticationKeyPair(privateKey: Data(repeating: 3, count: 32), publicKey: Data(repeating: 4, count: 32)),
				AuthenticationKeyPair(privateKey: Data(repeating: 5, count: 32), publicKey: Data(repeating: 6, count: 32)),
				AuthenticationKeyPair(privateKey: Data(repeating: 7, count: 32), publicKey: Data(repeating: 8, count: 32))
			]).next,
			randomBytes: { count in Data(repeating: UInt8(count), count: count) },
			signedPreKeySigner: signer
		)

		let credentials = try factory.makeCredentials()

		#expect(credentials.signedPreKey.signature == Data(repeating: 0x51, count: 64))
		#expect(adapter.signedPreKeySignatureRequests == [
			SignalSignedPreKeySignatureRequest(
				identityPrivateKey: Data(repeating: 1, count: 32),
				signedPreKeyPublicKey: Data(repeating: 8, count: 32)
			)
		])
	}

	@Test("native Signal adapter imports paired account identity")
	func nativeSignalAdapterImportsPairedAccountIdentity() async throws {
		let adapter = PublicNativeSignalAdapter(existingAddresses: [])
		let accountImporter: any SignalNativeAccountImporting = adapter
		let credentials = AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(
				privateKey: Data([5]),
				publicKey: Data([5]) + Data(repeating: 6, count: 32)
			),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(
					privateKey: Data([7]),
					publicKey: Data([5]) + Data(repeating: 8, count: 32)
				),
				signature: Data(repeating: 9, count: 64),
				keyID: 10
			),
			registrationID: 11,
			advSecretKey: "secret",
			me: WhatsAppUser(id: "123:4@s.whatsapp.net"),
			nextPreKeyID: 12,
			firstUnuploadedPreKeyID: 13,
			accountSyncCounter: 0,
			registered: true
		)

		try await accountImporter.importAccount(credentials: credentials)

		#expect(await adapter.accountImportRequests.map(\.localAddress) == [
			SignalProtocolAddress(name: "123", deviceID: 4)
		])
	}

	@Test("native Signal adapter configures authentication credentials factory")
	func nativeSignalAdapterConfiguresAuthenticationCredentialsFactory() throws {
		let adapter = PublicNativeSignalAdapter(existingAddresses: [])
		let factory = AuthenticationCredentialsFactory(
			nativeSignalAdapter: adapter,
			keyPairGenerator: PublicNativeAuthenticationKeyPairSequence([
				AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32)),
				AuthenticationKeyPair(privateKey: Data(repeating: 3, count: 32), publicKey: Data(repeating: 4, count: 32)),
				AuthenticationKeyPair(privateKey: Data(repeating: 5, count: 32), publicKey: Data(repeating: 6, count: 32)),
				AuthenticationKeyPair(privateKey: Data(repeating: 7, count: 32), publicKey: Data(repeating: 8, count: 32))
			]).next,
			randomBytes: { count in Data(repeating: UInt8(count), count: count) }
		)

		let credentials = try factory.makeCredentials()

		#expect(credentials.signedPreKey.signature == Data(repeating: 0x51, count: 64))
		#expect(adapter.signedPreKeySignatureRequests == [
			SignalSignedPreKeySignatureRequest(
				identityPrivateKey: Data(repeating: 1, count: 32),
				signedPreKeyPublicKey: Data(repeating: 8, count: 32)
			)
		])
	}

	@Test("native Signal adapter drives client text send path")
	func nativeSignalAdapterDrivesClientTextSendPath() async throws {
		let transport = PublicNativeSignalTransport()
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
					nextPreKeyID: 12,
					firstUnuploadedPreKeyID: 13,
					accountSyncCounter: 0,
					registered: false
				),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		await client.configureNativeSignalAdapter(
			adapter,
			query: publicNativeDependencyQuery
		)
		try await client.updateCredentials { credentials in
			credentials.me = WhatsAppUser(id: "999:0@s.whatsapp.net")
			credentials.registered = true
		}
		try await client.connect()

		let messageID = try await client.sendTextMessage(
			to: "123@s.whatsapp.net",
			text: "hello through native adapter",
			messageID: "3EB0NATIVE"
		)

		#expect(messageID == "3EB0NATIVE")
		#expect(await adapter.checkedAddresses == [[
			SignalSessionAddressCheck(jid: "123:0@s.whatsapp.net", address: SignalProtocolAddress(name: "123", deviceID: 0)),
			SignalSessionAddressCheck(jid: "123:1@s.whatsapp.net", address: SignalProtocolAddress(name: "123", deviceID: 1))
		]])
		#expect(await adapter.installedRequests.map(\.address) == [
			SignalProtocolAddress(name: "123", deviceID: 1)
		])
		#expect(await adapter.installedRequests.map(\.localAddress) == [
			SignalProtocolAddress(name: "999", deviceID: 0)
		])
		#expect(await adapter.directEncryptionRequests.map(\.address) == [
			SignalProtocolAddress(name: "123", deviceID: 0),
			SignalProtocolAddress(name: "123", deviceID: 1)
		])
		#expect(await adapter.directEncryptionRequests.map(\.localAddress) == [
			SignalProtocolAddress(name: "999", deviceID: 0),
			SignalProtocolAddress(name: "999", deviceID: 0)
		])
		#expect(await transport.sentFrames.count == 1)
	}

	@Test("native Signal adapter uses client query path by default")
	func nativeSignalAdapterUsesClientQueryPathByDefault() async throws {
		let transport = PublicNativeSignalTransport(respondsToQueries: true)
		let adapter = PublicNativeSignalAdapter(existingAddresses: [
			SignalProtocolAddress(name: "123", deviceID: 0)
		])
		let client = WhatsAppClient(transportFactory: { _ in transport })
		await client.configureNativeSignalAdapter(adapter)
		try await client.connect()

		let messageID = try await client.sendTextMessage(
			to: "123@s.whatsapp.net",
			text: "hello through client query",
			messageID: "3EB0QUERY"
		)

		#expect(messageID == "3EB0QUERY")
		#expect(await adapter.installedRequests.map(\.address) == [
			SignalProtocolAddress(name: "123", deviceID: 1)
		])
		#expect(await adapter.directEncryptionRequests.map(\.address) == [
			SignalProtocolAddress(name: "123", deviceID: 0),
			SignalProtocolAddress(name: "123", deviceID: 1)
		])
		#expect(await transport.sentNodes.map(\.tag) == ["iq", "iq", "message"])
		#expect(await transport.sentNodes.map { $0.attrs["xmlns"] ?? $0.attrs["category"] ?? "" } == [
			"usync",
			"encrypt",
			""
		])
	}

	@Test("native Signal adapter reads updated local identity after configuration")
	func nativeSignalAdapterReadsUpdatedLocalIdentityAfterConfiguration() async throws {
		let transport = PublicNativeSignalTransport()
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
					nextPreKeyID: 12,
					firstUnuploadedPreKeyID: 13,
					accountSyncCounter: 0,
					registered: false
				),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		await client.configureNativeSignalAdapter(adapter, query: publicNativeDependencyQuery)
		try await client.updateCredentials { credentials in
			credentials.me = WhatsAppUser(id: "999:0@s.whatsapp.net")
			credentials.registered = true
		}
		try await client.connect()

		_ = try await client.sendTextMessage(
			to: "123@s.whatsapp.net",
			text: "hello after pairing",
			messageID: "3EB0DYNAMIC"
		)

		#expect(await adapter.installedRequests.map(\.localAddress) == [
			SignalProtocolAddress(name: "999", deviceID: 0)
		])
		#expect(await adapter.directEncryptionRequests.map(\.localAddress) == [
			SignalProtocolAddress(name: "999", deviceID: 0),
			SignalProtocolAddress(name: "999", deviceID: 0)
		])
	}

	@Test("native Signal adapter handles low pre-key notifications")
	func nativeSignalAdapterHandlesLowPreKeyNotifications() async throws {
		let transport = PublicNativeSignalTransport(respondsToQueries: true)
		let adapter = PublicNativeSignalAdapter(existingAddresses: [])
		let client = WhatsAppClient(transportFactory: { _ in transport })
		var events = client.events.makeAsyncIterator()

		await client.configureNativeSignalAdapter(
			adapter,
			query: publicNativeDependencyQuery
		)
		try await client.connect()
		await transport.enqueueIncoming(BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "encrypt-native", "type": "encrypt"],
			content: .nodes([
				BinaryNode(tag: "count", attrs: ["value": "2"])
			])
		))

		#expect(await events.next() == .preKeyCountUpdated(PreKeyCountUpdate(
			count: 2,
			shouldUploadMorePreKeys: true
		)))
		for _ in 0..<50 {
			if await !adapter.preKeyUploadRequests.isEmpty { break }
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(await adapter.preKeyUploadRequests == [
			SignalPreKeyUploadRequest(currentCount: 2, requestedUploadCount: 5)
		])
		#expect(await publicNativeWaitForSentNodes(1, in: transport) == [
			BinaryNode(
				tag: "ack",
				attrs: ["id": "encrypt-native", "to": "@s.whatsapp.net", "class": "notification", "type": "encrypt"]
			)
		])
	}

	@Test("native Signal adapter receives credential-backed pre-key upload requests")
	func nativeSignalAdapterReceivesCredentialBackedPreKeyUploadRequests() async throws {
		let credentials = AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(
				privateKey: Data([5]),
				publicKey: Data([5]) + Data(repeating: 6, count: 32)
			),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(
					privateKey: Data([7]),
					publicKey: Data([5]) + Data(repeating: 8, count: 32)
				),
				signature: Data(repeating: 9, count: 64),
				keyID: 10
			),
			registrationID: 11,
			advSecretKey: "secret",
			nextPreKeyID: 12,
			firstUnuploadedPreKeyID: 13,
			accountSyncCounter: 0,
			registered: false
		)
		let transport = PublicNativeSignalTransport(respondsToQueries: true)
		let adapter = PublicNativeSignalAdapter(existingAddresses: [])
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(credentials: credentials, keys: InMemorySignalKeyStore()),
			transportFactory: { _ in transport }
		)
		var events = client.events.makeAsyncIterator()

		await client.configureNativeSignalAdapter(
			adapter,
			query: publicNativeDependencyQuery
		)
		try await client.connect()
		await transport.enqueueIncoming(BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "encrypt-native-auth", "type": "encrypt"],
			content: .nodes([
				BinaryNode(tag: "count", attrs: ["value": "2"])
			])
		))

		#expect(await events.next() == .preKeyCountUpdated(PreKeyCountUpdate(
			count: 2,
			shouldUploadMorePreKeys: true
		)))
		for _ in 0..<50 {
			if await !adapter.preKeyUploadRequests.isEmpty { break }
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(await adapter.preKeyUploadRequests == [
			SignalPreKeyUploadRequest(
				currentCount: 2,
				requestedUploadCount: 5,
				nativeUploadRequest: try credentials.nativePreKeyUploadRequest(
					currentServerPreKeyCount: 2,
					requestedUploadCount: 5
				)
			)
		])
	}

}
