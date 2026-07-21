import Foundation

public enum WhatsAppClientNativeSignalAccountError: Error, Equatable, Sendable {
	case missingImportedAccount(SignalNativeAccountImportRequest)
}

public enum SignalNativeOperationReadiness: Equatable, Sendable {
	case notChecked
	case ready
	case failed(String)

	public var isReady: Bool {
		self == .ready
	}

	public var failureDescription: String? {
		switch self {
		case .failed(let description):
			description
		case .notChecked:
			"notChecked"
		case .ready:
			nil
		}
	}
}

public enum SignalNativeAccountReadiness: Equatable, Sendable {
	case imported
	case missing
	case failed(String)

	public var isImported: Bool {
		self == .imported
	}

	public var failureDescription: String? {
		switch self {
		case .failed(let description):
			description
		case .imported, .missing:
			nil
		}
	}
}

public enum SignalNativeCredentialSigningReadiness: Equatable, Sendable {
	case notChecked
	case ready
	case failed(String)

	public var isReady: Bool {
		self == .ready
	}

	public var failureDescription: String? {
		switch self {
		case .failed(let description):
			description
		case .notChecked:
			"notChecked"
		case .ready:
			nil
		}
	}
}

public enum WhatsAppClientNativeMessageReadinessFailure: Equatable, Sendable {
	case signalOperationsNotChecked
	case signalOperationsFailed(String)
	case credentialSigningNotChecked
	case credentialSigningFailed(String)
	case nativeAccountMissing
	case nativeAccountFailed(String)
	case missingDependency(WhatsAppClientMessageCapability, WhatsAppClientMessageDependency)
}

public struct WhatsAppClientNativeMessageReadinessReport: Equatable, Sendable {
	public let accountRequest: SignalNativeAccountImportRequest
	public let signalOperationsReadiness: SignalNativeOperationReadiness
	public let credentialSigningReadiness: SignalNativeCredentialSigningReadiness
	public let nativeAccountReadiness: SignalNativeAccountReadiness
	public let requiredCapabilities: Set<WhatsAppClientMessageCapability>
	public let availableCapabilities: Set<WhatsAppClientMessageCapability>
	public let missingDependencies: [WhatsAppClientMessageCapability: [WhatsAppClientMessageDependency]]

	public var isSignalOperationsReady: Bool {
		signalOperationsReadiness.isReady
	}

	public var signalOperationsReadinessFailure: String? {
		signalOperationsReadiness.failureDescription
	}

	public var isCredentialSigningReady: Bool {
		credentialSigningReadiness.isReady
	}

	public var credentialSigningReadinessFailure: String? {
		credentialSigningReadiness.failureDescription
	}

	public var isNativeAccountImported: Bool {
		nativeAccountReadiness.isImported
	}

	public var nativeAccountReadinessFailure: String? {
		nativeAccountReadiness.failureDescription
	}

	public var isReady: Bool {
		isSignalOperationsReady && isCredentialSigningReady && isNativeAccountImported && missingDependencies.isEmpty
	}

	public var failures: [WhatsAppClientNativeMessageReadinessFailure] {
		var failures: [WhatsAppClientNativeMessageReadinessFailure] = []
		switch signalOperationsReadiness {
		case .notChecked:
			failures.append(.signalOperationsNotChecked)
		case .failed(let description):
			failures.append(.signalOperationsFailed(description))
		case .ready:
			break
		}
		switch credentialSigningReadiness {
		case .notChecked:
			failures.append(.credentialSigningNotChecked)
		case .failed(let description):
			failures.append(.credentialSigningFailed(description))
		case .ready:
			break
		}
		switch nativeAccountReadiness {
		case .missing:
			failures.append(.nativeAccountMissing)
		case .failed(let description):
			failures.append(.nativeAccountFailed(description))
		case .imported:
			break
		}
		for capability in WhatsAppClientMessageCapability.allCases where requiredCapabilities.contains(capability) {
			for dependency in missingDependencies[capability] ?? [] {
				failures.append(.missingDependency(capability, dependency))
			}
		}
		return failures
	}

	public init(
		accountRequest: SignalNativeAccountImportRequest,
		signalOperationsReadiness: SignalNativeOperationReadiness = .notChecked,
		credentialSigningReadiness: SignalNativeCredentialSigningReadiness = .notChecked,
		isNativeAccountImported: Bool,
		requiredCapabilities: Set<WhatsAppClientMessageCapability>,
		availableCapabilities: Set<WhatsAppClientMessageCapability>,
		missingDependencies: [WhatsAppClientMessageCapability: [WhatsAppClientMessageDependency]]
	) {
		self.accountRequest = accountRequest
		self.signalOperationsReadiness = signalOperationsReadiness
		self.credentialSigningReadiness = credentialSigningReadiness
		nativeAccountReadiness = isNativeAccountImported ? .imported : .missing
		self.requiredCapabilities = requiredCapabilities
		self.availableCapabilities = availableCapabilities
		self.missingDependencies = missingDependencies
	}

	public init(
		accountRequest: SignalNativeAccountImportRequest,
		signalOperationsReadiness: SignalNativeOperationReadiness = .notChecked,
		credentialSigningReadiness: SignalNativeCredentialSigningReadiness = .notChecked,
		nativeAccountReadiness: SignalNativeAccountReadiness,
		requiredCapabilities: Set<WhatsAppClientMessageCapability>,
		availableCapabilities: Set<WhatsAppClientMessageCapability>,
		missingDependencies: [WhatsAppClientMessageCapability: [WhatsAppClientMessageDependency]]
	) {
		self.accountRequest = accountRequest
		self.signalOperationsReadiness = signalOperationsReadiness
		self.credentialSigningReadiness = credentialSigningReadiness
		self.nativeAccountReadiness = nativeAccountReadiness
		self.requiredCapabilities = requiredCapabilities
		self.availableCapabilities = availableCapabilities
		self.missingDependencies = missingDependencies
	}

	public init(
		accountRequest: SignalNativeAccountImportRequest,
		isSignalOperationsReady: Bool = false,
		signalOperationsReadinessFailure: String? = "notChecked",
		isNativeAccountImported: Bool,
		requiredCapabilities: Set<WhatsAppClientMessageCapability>,
		availableCapabilities: Set<WhatsAppClientMessageCapability>,
		missingDependencies: [WhatsAppClientMessageCapability: [WhatsAppClientMessageDependency]]
	) {
		let readiness: SignalNativeOperationReadiness
		if isSignalOperationsReady {
			readiness = .ready
		} else if let signalOperationsReadinessFailure, signalOperationsReadinessFailure != "notChecked" {
			readiness = .failed(signalOperationsReadinessFailure)
		} else {
			readiness = .notChecked
		}

		self.init(
			accountRequest: accountRequest,
			signalOperationsReadiness: readiness,
			credentialSigningReadiness: .notChecked,
			isNativeAccountImported: isNativeAccountImported,
			requiredCapabilities: requiredCapabilities,
			availableCapabilities: availableCapabilities,
			missingDependencies: missingDependencies
		)
	}
}

extension WhatsAppClient {
	public func nativeMessageReadinessReport(
		capabilities: Set<WhatsAppClientMessageCapability> = Set(WhatsAppClientMessageCapability.allCases),
		accountChecker: any SignalNativeAccountImportChecking
	) async throws -> WhatsAppClientNativeMessageReadinessReport {
		let request = try nativeSignalAccountImportRequest()
		var missingByCapability: [WhatsAppClientMessageCapability: [WhatsAppClientMessageDependency]] = [:]

		for capability in capabilities {
			let missing = missingMessageDependencies(for: capability)
			if !missing.isEmpty {
				missingByCapability[capability] = missing
			}
		}

		let accountReadiness: SignalNativeAccountReadiness
		do {
			let imported = try await accountChecker.containsAccount(request)
			accountReadiness = imported ? .imported : .missing
		} catch {
			let failure = String(describing: type(of: error)).split(separator: ".").last.map(String.init)
			accountReadiness = .failed(failure ?? "Error")
		}
		return WhatsAppClientNativeMessageReadinessReport(
			accountRequest: request,
			nativeAccountReadiness: accountReadiness,
			requiredCapabilities: capabilities,
			availableCapabilities: availableMessageCapabilities(),
			missingDependencies: missingByCapability
		)
	}

	public func nativeMessageReadinessReport(
		capabilities: Set<WhatsAppClientMessageCapability> = Set(WhatsAppClientMessageCapability.allCases),
		using signalAdapter: any WhatsAppNativeSignalAdapter
	) async throws -> WhatsAppClientNativeMessageReadinessReport {
		let request = try nativeSignalAccountImportRequest()
		var missingByCapability: [WhatsAppClientMessageCapability: [WhatsAppClientMessageDependency]] = [:]

		for capability in capabilities {
			let missing = missingMessageDependencies(for: capability)
			if !missing.isEmpty {
				missingByCapability[capability] = missing
			}
		}

		let operationsReadiness: SignalNativeOperationReadiness
		do {
			try await signalAdapter.assertReadyForSignalOperations()
			operationsReadiness = .ready
		} catch {
			let failure = String(describing: type(of: error)).split(separator: ".").last.map(String.init)
			operationsReadiness = .failed(failure ?? "Error")
		}
		let credentialSigningReadiness: SignalNativeCredentialSigningReadiness
		do {
			try assertNativeCredentialSigning(using: signalAdapter)
			credentialSigningReadiness = .ready
		} catch {
			let failure = String(describing: type(of: error)).split(separator: ".").last.map(String.init)
			credentialSigningReadiness = .failed(failure ?? "Error")
		}
		let accountReadiness: SignalNativeAccountReadiness
		do {
			let imported = try await signalAdapter.containsAccount(request)
			accountReadiness = imported ? .imported : .missing
		} catch {
			let failure = String(describing: type(of: error)).split(separator: ".").last.map(String.init)
			accountReadiness = .failed(failure ?? "Error")
		}
		return WhatsAppClientNativeMessageReadinessReport(
			accountRequest: request,
			signalOperationsReadiness: operationsReadiness,
			credentialSigningReadiness: credentialSigningReadiness,
			nativeAccountReadiness: accountReadiness,
			requiredCapabilities: capabilities,
			availableCapabilities: availableMessageCapabilities(),
			missingDependencies: missingByCapability
		)
	}

	public func importNativeSignalAccount(
		using accountImporter: any SignalNativeAccountImporting
	) async throws -> SignalNativeAccountImportRequest {
		let request = try nativeSignalAccountImportRequest()
		try await accountImporter.importAccount(request)
		return request
	}

	public func importNativeSignalAccountIfNeeded(
		using accountStore: any SignalNativeAccountImporting & SignalNativeAccountImportChecking
	) async throws -> SignalNativeAccountImportResult {
		let request = try nativeSignalAccountImportRequest()
		if try await accountStore.containsAccount(request) {
			return SignalNativeAccountImportResult(request: request, imported: false)
		}

		try await accountStore.importAccount(request)
		return SignalNativeAccountImportResult(request: request, imported: true)
	}

	public func assertNativeSignalAccountImported(
		using accountChecker: any SignalNativeAccountImportChecking
	) async throws -> SignalNativeAccountImportRequest {
		let request = try nativeSignalAccountImportRequest()
		if try await accountChecker.containsAccount(request) {
			return request
		}

		throw WhatsAppClientNativeSignalAccountError.missingImportedAccount(request)
	}

	public func assertNativeMessageReadiness(
		capabilities: Set<WhatsAppClientMessageCapability> = Set(WhatsAppClientMessageCapability.allCases),
		accountChecker: any SignalNativeAccountImportChecking
	) async throws -> SignalNativeAccountImportRequest {
		try assertMessageCapabilities(capabilities)
		return try await assertNativeSignalAccountImported(using: accountChecker)
	}

	public func assertNativeMessageReadiness(
		capabilities: Set<WhatsAppClientMessageCapability> = Set(WhatsAppClientMessageCapability.allCases),
		using signalAdapter: any WhatsAppNativeSignalAdapter
	) async throws -> SignalNativeAccountImportRequest {
		try assertMessageCapabilities(capabilities)
		try await signalAdapter.assertReadyForSignalOperations()
		try assertNativeCredentialSigning(using: signalAdapter)
		return try await assertNativeSignalAccountImported(using: signalAdapter)
	}

	public func ensureNativeMessageReadiness(
		capabilities: Set<WhatsAppClientMessageCapability> = Set(WhatsAppClientMessageCapability.allCases),
		using accountStore: any SignalNativeAccountImporting & SignalNativeAccountImportChecking
	) async throws -> SignalNativeAccountImportResult {
		try assertMessageCapabilities(capabilities)
		return try await importNativeSignalAccountIfNeeded(using: accountStore)
	}

	public func ensureNativeMessageReadiness(
		capabilities: Set<WhatsAppClientMessageCapability> = Set(WhatsAppClientMessageCapability.allCases),
		using signalAdapter: any WhatsAppNativeSignalAdapter
	) async throws -> SignalNativeAccountImportResult {
		try assertMessageCapabilities(capabilities)
		try await signalAdapter.assertReadyForSignalOperations()
		try assertNativeCredentialSigning(using: signalAdapter)
		return try await importNativeSignalAccountIfNeeded(using: signalAdapter)
	}

	private func nativeSignalAccountImportRequest() throws -> SignalNativeAccountImportRequest {
		guard let authenticationState else {
			throw WhatsAppClientError.missingAuthenticationState
		}

		return try authenticationState.credentials.nativeAccountImportRequest()
	}

	private func assertNativeCredentialSigning(using signer: any SignalSignedPreKeySigning) throws {
		do {
			try signer.assertReadyForCredentialSigning()
		} catch SignalSignedPreKeySigningError.invalidSignedPreKeySignature {
			throw WhatsAppNativeSignalBackendAdapterError.invalidSignedPreKeySignature
		}
	}
}
