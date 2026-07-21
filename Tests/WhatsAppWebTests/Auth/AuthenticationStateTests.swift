import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Authentication state")
struct AuthenticationStateTests {
	@Test("loads existing credentials without creating new credentials")
	func loadsExistingCredentialsWithoutCreatingNewCredentials() async throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("swift-baileys-state-\(UUID().uuidString)", isDirectory: true)
		let store = FileAuthenticationStore(directory: directory)
		let credentials = sampleCredentials(registrationID: 111)
		let factory = CountingCredentialsFactory(credentials: sampleCredentials(registrationID: 222))
		try await store.saveCredentials(credentials)

		let state = try await AuthenticationState.loadOrCreate(store: store, credentialsFactory: factory.makeCredentials)

		#expect(state.credentials == credentials)
		#expect(factory.makeCount == 0)
		#expect(try await state.keys.get(.session, ids: ["missing"]).isEmpty)
	}

	@Test("creates and saves credentials when none exist")
	func createsAndSavesCredentialsWhenNoneExist() async throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("swift-baileys-state-\(UUID().uuidString)", isDirectory: true)
		let store = FileAuthenticationStore(directory: directory)
		let credentials = sampleCredentials(registrationID: 333)
		let factory = CountingCredentialsFactory(credentials: credentials)

		let state = try await AuthenticationState.loadOrCreate(store: store, credentialsFactory: factory.makeCredentials)
		let reloaded = try await store.loadCredentials()

		#expect(state.credentials == credentials)
		#expect(reloaded == credentials)
		#expect(factory.makeCount == 1)
	}

	@Test("updates credentials and persists them")
	func updatesCredentialsAndPersistsThem() async throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("swift-baileys-state-\(UUID().uuidString)", isDirectory: true)
		let store = FileAuthenticationStore(directory: directory)
		let credentials = sampleCredentials(registrationID: 444)
		var state = try await AuthenticationState.loadOrCreate(
			store: store,
			credentialsFactory: CountingCredentialsFactory(credentials: credentials).makeCredentials
		)

		try await state.updateCredentials { credentials in
			credentials.registered = true
			credentials.me = WhatsAppUser(id: "123@s.whatsapp.net", name: "Swift User")
		}

		#expect(state.credentials.registered == true)
		#expect(state.credentials.me == WhatsAppUser(id: "123@s.whatsapp.net", name: "Swift User"))
		#expect(try await store.loadCredentials() == state.credentials)
	}

	private func sampleCredentials(registrationID: Int) -> AuthenticationCredentials {
		AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data([6])),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([8])),
				signature: Data([9]),
				keyID: 1
			),
			registrationID: registrationID,
			advSecretKey: "adv-secret",
			nextPreKeyID: 1,
			firstUnuploadedPreKeyID: 1,
			accountSyncCounter: 0,
			registered: false
		)
	}
}

private final class CountingCredentialsFactory: @unchecked Sendable {
	private let lock = NSLock()
	private let credentials: AuthenticationCredentials
	private var count = 0

	init(credentials: AuthenticationCredentials) {
		self.credentials = credentials
	}

	var makeCount: Int {
		lock.withLock {
			count
		}
	}

	func makeCredentials() throws -> AuthenticationCredentials {
		lock.withLock {
			count += 1
		}
		return credentials
	}
}
