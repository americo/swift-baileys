import Foundation
import Testing
import WhatsAppWeb

@Suite("Public native Signal account import")
struct PublicNativeSignalAccountImportTests {
	@Test("client imports current account identity into native Signal adapter")
	func clientImportsCurrentAccountIdentityIntoNativeSignalAdapter() async throws {
		let adapter = PublicNativeSignalAdapter(existingAddresses: [])
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
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: credentials,
			keys: InMemorySignalKeyStore()
		))

		let request = try await client.importNativeSignalAccount(using: adapter)

		#expect(request.localAddress == SignalProtocolAddress(name: "123", deviceID: 4))
		#expect(await adapter.accountImportRequests == [request])
	}

	@Test("client account import requires authentication state")
	func clientAccountImportRequiresAuthenticationState() async throws {
		let adapter = PublicNativeSignalAdapter(existingAddresses: [])
		let client = WhatsAppClient()

		await #expect(throws: WhatsAppClientError.missingAuthenticationState) {
			try await client.importNativeSignalAccount(using: adapter)
		}
	}

	@Test("client skips native account import when store already has the account")
	func clientSkipsNativeAccountImportWhenStoreAlreadyHasTheAccount() async throws {
		let adapter = PublicNativeSignalAccountStore(hasAccount: true)
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: pairedCredentials(),
			keys: InMemorySignalKeyStore()
		))

		let result = try await client.importNativeSignalAccountIfNeeded(using: adapter)

		#expect(result.imported == false)
		#expect(result.request.localAddress == SignalProtocolAddress(name: "123", deviceID: 4))
		#expect(await adapter.importedRequests.isEmpty)
		#expect(await adapter.checkedRequests == [result.request])
	}

	@Test("client imports native account when store is missing the account")
	func clientImportsNativeAccountWhenStoreIsMissingTheAccount() async throws {
		let adapter = PublicNativeSignalAccountStore(hasAccount: false)
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: pairedCredentials(),
			keys: InMemorySignalKeyStore()
		))

		let result = try await client.importNativeSignalAccountIfNeeded(using: adapter)

		#expect(result.imported)
		#expect(await adapter.importedRequests == [result.request])
		#expect(await adapter.checkedRequests == [result.request])
	}

	@Test("client asserts native account already imported")
	func clientAssertsNativeAccountAlreadyImported() async throws {
		let adapter = PublicNativeSignalAccountStore(hasAccount: true)
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: pairedCredentials(),
			keys: InMemorySignalKeyStore()
		))

		let request = try await client.assertNativeSignalAccountImported(using: adapter)

		#expect(request.localAddress == SignalProtocolAddress(name: "123", deviceID: 4))
		#expect(await adapter.checkedRequests == [request])
		#expect(await adapter.importedRequests.isEmpty)
	}

	@Test("client account import assertion fails when native store is missing account")
	func clientAccountImportAssertionFailsWhenNativeStoreIsMissingAccount() async throws {
		let adapter = PublicNativeSignalAccountStore(hasAccount: false)
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: pairedCredentials(),
			keys: InMemorySignalKeyStore()
		))
		let expectedRequest = try pairedCredentials().nativeAccountImportRequest()

		await #expect(throws: WhatsAppClientNativeSignalAccountError.missingImportedAccount(expectedRequest)) {
			try await client.assertNativeSignalAccountImported(using: adapter)
		}
		#expect(await adapter.checkedRequests == [expectedRequest])
		#expect(await adapter.importedRequests.isEmpty)
	}

	@Test("client asserts native message readiness")
	func clientAssertsNativeMessageReadiness() async throws {
		let adapter = PublicNativeSignalAccountStore(hasAccount: true)
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: pairedCredentials(),
				keys: InMemorySignalKeyStore()
			),
			messageDependencies: readinessDependencies()
		)

		let request = try await client.assertNativeMessageReadiness(
			capabilities: [.directSend, .incomingDecrypt],
			accountChecker: adapter
		)

		#expect(request.localAddress == SignalProtocolAddress(name: "123", deviceID: 4))
		#expect(await adapter.checkedRequests == [request])
		#expect(await adapter.importedRequests.isEmpty)
	}

	@Test("client native message readiness fails before account check when dependencies are missing")
	func clientNativeMessageReadinessFailsBeforeAccountCheckWhenDependenciesAreMissing() async throws {
		let adapter = PublicNativeSignalAccountStore(hasAccount: true)
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: pairedCredentials(),
			keys: InMemorySignalKeyStore()
		))

		await #expect(throws: WhatsAppClientMessageDependencyError(missingByCapability: [
			.directSend: [
				.messageEncryptor,
				.messageDeviceResolver,
				.signalSessionPreparer
			]
		])) {
			try await client.assertNativeMessageReadiness(
				capabilities: [.directSend],
				accountChecker: adapter
			)
		}
		#expect(await adapter.checkedRequests.isEmpty)
	}
}

private actor PublicNativeSignalAccountStore: SignalNativeAccountImporting, SignalNativeAccountImportChecking {
	private let hasAccount: Bool
	private(set) var checkedRequests: [SignalNativeAccountImportRequest] = []
	private(set) var importedRequests: [SignalNativeAccountImportRequest] = []

	init(hasAccount: Bool) {
		self.hasAccount = hasAccount
	}

	func containsAccount(_ request: SignalNativeAccountImportRequest) async throws -> Bool {
		checkedRequests.append(request)
		return hasAccount
	}

	func importAccount(_ request: SignalNativeAccountImportRequest) async throws {
		importedRequests.append(request)
	}
}

private func pairedCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
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
}

private func readinessDependencies() -> WhatsAppClientMessageDependencies {
	WhatsAppClientMessageDependencies(
		messageEncryptor: ReadinessNativeMessageAdapter(),
		groupMessageEncryptor: ReadinessNativeMessageAdapter(),
		messageDeviceResolver: ReadinessNativeDeviceResolver(),
		signalSessionPreparer: ReadinessNativeSessionPreparer(),
		incomingSignalDecryptor: ReadinessNativeSignalDecryptor()
	)
}

private actor ReadinessNativeMessageAdapter: MessageEncrypting, GroupMessageEncrypting {
	func encryptMessage(jid: String, data: Data) async throws -> EncryptedMessage {
		EncryptedMessage(type: "msg", ciphertext: data)
	}

	func encryptGroupMessage(group: String, senderJID: String, data: Data) async throws -> EncryptedGroupMessage {
		EncryptedGroupMessage(ciphertext: data, senderKeyDistributionMessage: Data([1]))
	}
}

private struct ReadinessNativeDeviceResolver: MessageDeviceResolving {
	func deviceJIDs(for jid: String) async throws -> [String] {
		[jid]
	}
}

private struct ReadinessNativeSessionPreparer: SignalSessionPreparing {
	func assertSessions(for jids: [String], force: Bool) async throws -> Bool {
		!jids.isEmpty
	}
}

private struct ReadinessNativeSignalDecryptor: SignalMessageDecrypting {
	func decryptMessage(jid: String, type: String, ciphertext: Data) async throws -> Data {
		ciphertext
	}

	func decryptGroupMessage(group: String, authorJID: String, ciphertext: Data) async throws -> Data {
		ciphertext
	}

	func processSenderKeyDistributionMessage(authorJID: String, messageData: Data) async throws {}
}
