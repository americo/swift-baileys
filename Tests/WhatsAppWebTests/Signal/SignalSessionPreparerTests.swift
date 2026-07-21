import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Signal session preparer")
struct SignalSessionPreparerTests {
	@Test("fetches and injects bundles only for missing sessions")
	func fetchesAndInjectsBundlesOnlyForMissingSessions() async throws {
		let keys = InMemorySignalKeyStore(storage: [
			.session: ["existing.0": Data([0xee])]
		])
		let bundleResolver = StubSignalBundleResolving(result: [
			sampleBundle(jid: "missing@s.whatsapp.net")
		])
		let injector = RecordingSignalSessionInjector()
		let preparer = SignalSessionPreparer(
			keys: keys,
			bundleResolver: bundleResolver,
			sessionInjector: injector
		)

		let didFetch = try await preparer.assertSessions(
			for: ["existing@s.whatsapp.net", "missing@s.whatsapp.net", "missing@s.whatsapp.net"]
		)

		#expect(didFetch == true)
		#expect(await bundleResolver.calls == [
			SignalBundleFetchCall(jids: ["missing@s.whatsapp.net"], force: false)
		])
		#expect(await injector.bundles == [sampleBundle(jid: "missing@s.whatsapp.net")])
	}

	@Test("force refresh fetches all unique sessions")
	func forceRefreshFetchesAllUniqueSessions() async throws {
		let keys = InMemorySignalKeyStore(storage: [
			.session: ["existing@s.whatsapp.net": Data([0xee])]
		])
		let bundleResolver = StubSignalBundleResolving(result: [
			sampleBundle(jid: "existing@s.whatsapp.net"),
			sampleBundle(jid: "missing@s.whatsapp.net")
		])
		let injector = RecordingSignalSessionInjector()
		let preparer = SignalSessionPreparer(keys: keys, bundleResolver: bundleResolver, sessionInjector: injector)

		let didFetch = try await preparer.assertSessions(
			for: ["existing@s.whatsapp.net", "missing@s.whatsapp.net"],
			force: true
		)

		#expect(didFetch == true)
		#expect(await bundleResolver.calls == [
			SignalBundleFetchCall(jids: ["existing@s.whatsapp.net", "missing@s.whatsapp.net"], force: true)
		])
		#expect(await injector.bundles.count == 2)
	}

	@Test("does not fetch when all sessions exist")
	func doesNotFetchWhenAllSessionsExist() async throws {
		let keys = InMemorySignalKeyStore(storage: [
			.session: ["existing.0": Data([0xee])]
		])
		let bundleResolver = StubSignalBundleResolving(result: [])
		let preparer = SignalSessionPreparer(
			keys: keys,
			bundleResolver: bundleResolver,
			sessionInjector: RecordingSignalSessionInjector()
		)

		let didFetch = try await preparer.assertSessions(for: ["existing@s.whatsapp.net"])

		#expect(didFetch == false)
		#expect(await bundleResolver.calls.isEmpty)
	}

	@Test("checks stored sessions using Signal protocol address keys")
	func checksStoredSessionsUsingSignalProtocolAddressKeys() async throws {
		let keys = InMemorySignalKeyStore(storage: [
			.session: [
				"123.1": Data([0xee]),
				"abc_1.9": Data([0xdd])
			]
		])
		let bundleResolver = StubSignalBundleResolving(result: [])
		let preparer = SignalSessionPreparer(
			keys: keys,
			bundleResolver: bundleResolver,
			sessionInjector: RecordingSignalSessionInjector()
		)

		let didFetch = try await preparer.assertSessions(for: ["123:1@s.whatsapp.net", "abc:9@lid"])

		#expect(didFetch == false)
		#expect(await bundleResolver.calls.isEmpty)
	}

	@Test("rejects invalid requested JIDs before fetching bundles")
	func rejectsInvalidRequestedJIDsBeforeFetchingBundles() async throws {
		let bundleResolver = StubSignalBundleResolving(result: [])
		let preparer = SignalSessionPreparer(
			keys: InMemorySignalKeyStore(),
			bundleResolver: bundleResolver,
			sessionInjector: RecordingSignalSessionInjector()
		)

		await #expect(throws: SignalSessionPreparationError.invalidJID("123:bad@s.whatsapp.net")) {
			try await preparer.assertSessions(for: ["123:bad@s.whatsapp.net"])
		}
		#expect(await bundleResolver.calls.isEmpty)
	}

	@Test("uses injected session checker before fetching bundles")
	func usesInjectedSessionCheckerBeforeFetchingBundles() async throws {
		let checker = StubSignalSessionChecker(existingJIDs: ["native@s.whatsapp.net"])
		let bundleResolver = StubSignalBundleResolving(result: [
			sampleBundle(jid: "missing@s.whatsapp.net")
		])
		let injector = RecordingSignalSessionInjector()
		let preparer = SignalSessionPreparer(
			sessionChecker: checker,
			bundleResolver: bundleResolver,
			sessionInjector: injector
		)

		let didFetch = try await preparer.assertSessions(
			for: ["native@s.whatsapp.net", "missing@s.whatsapp.net"]
		)

		#expect(didFetch)
		#expect(await checker.calls == [["native@s.whatsapp.net", "missing@s.whatsapp.net"]])
		#expect(await bundleResolver.calls == [
			SignalBundleFetchCall(jids: ["missing@s.whatsapp.net"], force: false)
		])
		#expect(await injector.bundles == [sampleBundle(jid: "missing@s.whatsapp.net")])
	}

	@Test("uses injected address session checker with normalized Signal addresses")
	func usesInjectedAddressSessionCheckerWithNormalizedSignalAddresses() async throws {
		let checker = StubSignalSessionAddressChecker(existingAddresses: [
			SignalProtocolAddress(name: "123", deviceID: 1)
		])
		let bundleResolver = StubSignalBundleResolving(result: [
			sampleBundle(jid: "abc:9@lid")
		])
		let injector = RecordingSignalSessionInjector()
		let preparer = SignalSessionPreparer(
			addressChecker: checker,
			bundleResolver: bundleResolver,
			sessionInjector: injector
		)

		let didFetch = try await preparer.assertSessions(for: [
			"123:1@s.whatsapp.net",
			"abc:9@lid"
		])

		#expect(didFetch)
		#expect(await checker.calls == [[
			SignalSessionAddressCheck(jid: "123:1@s.whatsapp.net", address: SignalProtocolAddress(name: "123", deviceID: 1)),
			SignalSessionAddressCheck(jid: "abc:9@lid", address: SignalProtocolAddress(name: "abc_1", deviceID: 9))
		]])
		#expect(await bundleResolver.calls == [
			SignalBundleFetchCall(jids: ["abc:9@lid"], force: false)
		])
		#expect(await injector.bundles == [sampleBundle(jid: "abc:9@lid")])
	}

	@Test("rejects bundles without a valid Signal address before injection")
	func rejectsBundlesWithoutValidSignalAddressBeforeInjection() async throws {
		let bundleResolver = StubSignalBundleResolving(result: [
			sampleBundle(jid: "missing:bad@s.whatsapp.net")
		])
		let injector = RecordingSignalSessionInjector()
		let preparer = SignalSessionPreparer(
			keys: InMemorySignalKeyStore(),
			bundleResolver: bundleResolver,
			sessionInjector: injector
		)

		await #expect(throws: SignalSessionPreparationError.invalidBundle) {
			try await preparer.assertSessions(for: ["missing@s.whatsapp.net"])
		}
		#expect(await injector.bundles.isEmpty)
	}

	@Test("rejects bundles for JIDs that were not requested")
	func rejectsBundlesForJIDsThatWereNotRequested() async throws {
		let bundleResolver = StubSignalBundleResolving(result: [
			sampleBundle(jid: "other@s.whatsapp.net")
		])
		let injector = RecordingSignalSessionInjector()
		let preparer = SignalSessionPreparer(
			keys: InMemorySignalKeyStore(),
			bundleResolver: bundleResolver,
			sessionInjector: injector
		)

		await #expect(throws: SignalSessionPreparationError.invalidBundle) {
			try await preparer.assertSessions(for: ["missing@s.whatsapp.net"])
		}
		#expect(await injector.bundles.isEmpty)
	}

	@Test("rejects missing bundles for requested JIDs")
	func rejectsMissingBundlesForRequestedJIDs() async throws {
		let bundleResolver = StubSignalBundleResolving(result: [
			sampleBundle(jid: "first@s.whatsapp.net")
		])
		let injector = RecordingSignalSessionInjector()
		let preparer = SignalSessionPreparer(
			keys: InMemorySignalKeyStore(),
			bundleResolver: bundleResolver,
			sessionInjector: injector
		)

		await #expect(throws: SignalSessionPreparationError.missingBundle) {
			try await preparer.assertSessions(for: ["first@s.whatsapp.net", "second@s.whatsapp.net"])
		}
		#expect(await injector.bundles.isEmpty)
	}

	@Test("rejects bundles with invalid Signal key material before injection")
	func rejectsBundlesWithInvalidSignalKeyMaterialBeforeInjection() async throws {
		let bundleResolver = StubSignalBundleResolving(result: [
			SignalSessionBundle(
				jid: "missing@s.whatsapp.net",
				registrationID: 7,
				identityKey: Data([5, 1]),
				signedPreKey: SignalPreKey(keyID: 1, publicKey: Data([5, 2]), signature: Data(repeating: 3, count: 64)),
				preKey: SignalPreKey(keyID: 2, publicKey: Data([4, 4]), signature: nil)
			)
		])
		let injector = RecordingSignalSessionInjector()
		let preparer = SignalSessionPreparer(
			keys: InMemorySignalKeyStore(),
			bundleResolver: bundleResolver,
			sessionInjector: injector
		)

		await #expect(throws: SignalSessionPreparationError.invalidBundle) {
			try await preparer.assertSessions(for: ["missing@s.whatsapp.net"])
		}
		#expect(await injector.bundles.isEmpty)
	}

	private func sampleBundle(jid: String) -> SignalSessionBundle {
		SignalSessionBundle(
			jid: jid,
			registrationID: 7,
			identityKey: Data([5]) + Data(repeating: 1, count: 32),
			signedPreKey: SignalPreKey(
				keyID: 1,
				publicKey: Data([5]) + Data(repeating: 2, count: 32),
				signature: Data(repeating: 3, count: 64)
			),
			preKey: SignalPreKey(keyID: 2, publicKey: Data([5]) + Data(repeating: 4, count: 32), signature: nil)
		)
	}
}

private actor StubSignalBundleResolving: SignalBundleResolving {
	private let result: [SignalSessionBundle]
	private(set) var calls: [SignalBundleFetchCall] = []

	init(result: [SignalSessionBundle]) {
		self.result = result
	}

	func fetchBundles(for jids: [String], force: Bool) async throws -> [SignalSessionBundle] {
		calls.append(SignalBundleFetchCall(jids: jids, force: force))
		return result
	}
}

private actor RecordingSignalSessionInjector: SignalSessionInjecting {
	private(set) var bundles: [SignalSessionBundle] = []

	func injectSession(bundle: SignalSessionBundle) async throws {
		bundles.append(bundle)
	}
}

private actor StubSignalSessionChecker: SignalSessionChecking {
	private let existingJIDs: Set<String>
	private(set) var calls: [[String]] = []

	init(existingJIDs: Set<String>) {
		self.existingJIDs = existingJIDs
	}

	func existingSessions(for jids: [String]) async throws -> Set<String> {
		calls.append(jids)
		return Set(jids.filter(existingJIDs.contains))
	}
}

private actor StubSignalSessionAddressChecker: SignalSessionAddressChecking {
	private let existingAddresses: Set<SignalProtocolAddress>
	private(set) var calls: [[SignalSessionAddressCheck]] = []

	init(existingAddresses: Set<SignalProtocolAddress>) {
		self.existingAddresses = existingAddresses
	}

	func existingSessions(for checks: [SignalSessionAddressCheck]) async throws -> Set<SignalProtocolAddress> {
		calls.append(checks)
		return Set(checks.map(\.address).filter(existingAddresses.contains))
	}
}
