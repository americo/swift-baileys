import Foundation

struct SignalBundleFetchCall: Equatable, Sendable {
	let jids: [String]
	let force: Bool
}

public protocol SignalBundleResolving: Sendable {
	func fetchBundles(for jids: [String], force: Bool) async throws -> [SignalSessionBundle]
}

public protocol SignalSessionInjecting: Sendable {
	func injectSession(bundle: SignalSessionBundle) async throws
}

public protocol SignalNativeSessionInstalling: SignalSessionInjecting {
	func installSession(_ request: SignalSessionNativeInstallRequest) async throws
}

public extension SignalNativeSessionInstalling {
	func injectSession(bundle: SignalSessionBundle) async throws {
		try await installSession(bundle.nativeInstallRequest())
	}
}

public protocol SignalSessionPreparing: Sendable {
	func assertSessions(for jids: [String], force: Bool) async throws -> Bool
}

public protocol SignalSessionChecking: Sendable {
	func existingSessions(for jids: [String]) async throws -> Set<String>
}

public struct SignalSessionAddressCheck: Equatable, Hashable, Sendable {
	public let jid: String
	public let address: SignalProtocolAddress

	public init(jid: String, address: SignalProtocolAddress) {
		self.jid = jid
		self.address = address
	}
}

public protocol SignalSessionAddressChecking: Sendable {
	func existingSessions(for checks: [SignalSessionAddressCheck]) async throws -> Set<SignalProtocolAddress>
}

public enum SignalSessionPreparationError: Error, Equatable, Sendable {
	case invalidJID(String)
	case invalidBundle
	case missingBundle
}

public struct SignalSessionPreparer: SignalSessionPreparing {
	private let sessionChecker: any SignalSessionChecking
	private let bundleResolver: any SignalBundleResolving
	private let sessionInjector: any SignalSessionInjecting
	private let localJIDProvider: @Sendable () async -> String?

	public init(
		keys: any SignalKeyStore,
		bundleResolver: any SignalBundleResolving,
		sessionInjector: any SignalSessionInjecting,
		localJID: String? = nil
	) {
		self.sessionChecker = SignalKeyStoreSessionChecker(keys: keys)
		self.bundleResolver = bundleResolver
		self.sessionInjector = sessionInjector
		self.localJIDProvider = { localJID }
	}

	public init(
		sessionChecker: any SignalSessionChecking,
		bundleResolver: any SignalBundleResolving,
		sessionInjector: any SignalSessionInjecting,
		localJID: String? = nil
	) {
		self.sessionChecker = sessionChecker
		self.bundleResolver = bundleResolver
		self.sessionInjector = sessionInjector
		self.localJIDProvider = { localJID }
	}

	public init(
		addressChecker: any SignalSessionAddressChecking,
		bundleResolver: any SignalBundleResolving,
		sessionInjector: any SignalSessionInjecting,
		localJID: String? = nil
	) {
		self.init(
			addressChecker: addressChecker,
			bundleResolver: bundleResolver,
			sessionInjector: sessionInjector,
			localJIDProvider: { localJID }
		)
	}

	public init(
		addressChecker: any SignalSessionAddressChecking,
		bundleResolver: any SignalBundleResolving,
		sessionInjector: any SignalSessionInjecting,
		localJIDProvider: @escaping @Sendable () async -> String?
	) {
		self.sessionChecker = SignalSessionAddressCheckerAdapter(addressChecker: addressChecker)
		self.bundleResolver = bundleResolver
		self.sessionInjector = sessionInjector
		self.localJIDProvider = localJIDProvider
	}

	public func assertSessions(for jids: [String], force: Bool = false) async throws -> Bool {
		let uniqueJIDs = orderedUnique(jids)
		for jid in uniqueJIDs where SignalProtocolAddress(jid: jid) == nil {
			throw SignalSessionPreparationError.invalidJID(jid)
		}

		let jidsRequiringFetch: [String]

		if force {
			jidsRequiringFetch = uniqueJIDs
		} else {
			let existingSessions = try await sessionChecker.existingSessions(for: uniqueJIDs)
			jidsRequiringFetch = uniqueJIDs.filter { !existingSessions.contains($0) }
		}

		if jidsRequiringFetch.isEmpty {
			return false
		}

		let bundles = try await bundleResolver.fetchBundles(for: jidsRequiringFetch, force: force)
		let requestedJIDs = Set(jidsRequiringFetch)
		var returnedJIDs = Set<String>()
		for bundle in bundles {
			guard (try? bundle.validatedAddress()) != nil,
				  requestedJIDs.contains(bundle.jid) else {
				throw SignalSessionPreparationError.invalidBundle
			}

			returnedJIDs.insert(bundle.jid)
		}

		guard returnedJIDs == requestedJIDs else {
			throw SignalSessionPreparationError.missingBundle
		}

		for bundle in bundles {
			if let nativeInstaller = sessionInjector as? any SignalNativeSessionInstalling {
				try await nativeInstaller.installSession(bundle.nativeInstallRequest(localJID: await localJIDProvider()))
			} else {
				try await sessionInjector.injectSession(bundle: bundle)
			}
		}

		return true
	}

	private func orderedUnique(_ values: [String]) -> [String] {
		var seen = Set<String>()
		var result: [String] = []

		for value in values where !seen.contains(value) {
			seen.insert(value)
			result.append(value)
		}

		return result
	}
}

private struct SignalSessionAddressCheckerAdapter: SignalSessionChecking {
	let addressChecker: any SignalSessionAddressChecking

	func existingSessions(for jids: [String]) async throws -> Set<String> {
		let checks = jids.compactMap { jid -> SignalSessionAddressCheck? in
			guard let address = SignalProtocolAddress(jid: jid) else {
				return nil
			}

			return SignalSessionAddressCheck(jid: jid, address: address)
		}
		let existingAddresses = try await addressChecker.existingSessions(for: checks)
		return Set(checks.compactMap { existingAddresses.contains($0.address) ? $0.jid : nil })
	}
}

extension SignalSessionBundleResolver: SignalBundleResolving {}

private struct SignalKeyStoreSessionChecker: SignalSessionChecking {
	let keys: any SignalKeyStore

	func existingSessions(for jids: [String]) async throws -> Set<String> {
		var jidsByStorageKey: [String: String] = [:]
		for jid in jids {
			guard let address = SignalProtocolAddress(jid: jid) else {
				continue
			}

			jidsByStorageKey[address.storageKey] = jid
		}

		let sessions = try await keys.get(.session, ids: Array(jidsByStorageKey.keys))
		return Set(sessions.keys.compactMap { jidsByStorageKey[$0] })
	}
}
