import Foundation
import Testing
import WhatsAppWeb

@Suite("Public native Signal readiness")
struct PublicNativeSignalReadinessTests {
	@Test("native Signal adapter exposes operation readiness preflight")
	func nativeSignalAdapterExposesOperationReadinessPreflight() async throws {
		let adapter = PublicNativeSignalAdapter(existingAddresses: [])
		let signalAdapter: any WhatsAppNativeSignalAdapter = adapter

		try await signalAdapter.assertReadyForSignalOperations()

		#expect(await adapter.readinessCheckCount == 1)
	}

	@Test("native Signal adapter can gate client message readiness")
	func nativeSignalAdapterCanGateClientMessageReadiness() async throws {
		let adapter = PublicNativeSignalAdapter(
			existingAddresses: [],
			existingAccountAddresses: [SignalProtocolAddress(name: "999", deviceID: 0)]
		)
		let signalAdapter: any WhatsAppNativeSignalAdapter = adapter
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: publicNativePairedCredentials(),
			keys: InMemorySignalKeyStore()
		))
		await client.configureNativeSignalAdapter(
			signalAdapter,
			query: publicNativeDependencyQuery,
			mediaUploader: PublicMediaUploader()
		)

		let request = try await client.assertNativeMessageReadiness(accountChecker: signalAdapter)

		#expect(request.localAddress == SignalProtocolAddress(name: "999", deviceID: 0))
		#expect(await adapter.accountCheckRequests == [request])
	}

	@Test("native Signal adapter readiness gate runs operation preflight")
	func nativeSignalAdapterReadinessGateRunsOperationPreflight() async throws {
		let adapter = PublicNativeSignalAdapter(
			existingAddresses: [],
			existingAccountAddresses: [SignalProtocolAddress(name: "999", deviceID: 0)]
		)
		let signalAdapter: any WhatsAppNativeSignalAdapter = adapter
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: publicNativePairedCredentials(),
			keys: InMemorySignalKeyStore()
		))
		await client.configureNativeSignalAdapter(
			signalAdapter,
			query: publicNativeDependencyQuery,
			mediaUploader: PublicMediaUploader()
		)

		let request = try await client.assertNativeMessageReadiness(using: signalAdapter)

		#expect(request.localAddress == SignalProtocolAddress(name: "999", deviceID: 0))
		#expect(await adapter.readinessCheckCount == 1)
		#expect(await adapter.accountCheckRequests == [request])
	}

	@Test("native Signal adapter readiness gate rejects invalid credential signing")
	func nativeSignalAdapterReadinessGateRejectsInvalidCredentialSigning() async throws {
		let adapter = PublicNativeSignalAdapter(
			existingAddresses: [],
			existingAccountAddresses: [SignalProtocolAddress(name: "999", deviceID: 0)],
			signedPreKeySignature: Data(repeating: 0x51, count: 63)
		)
		let signalAdapter: any WhatsAppNativeSignalAdapter = adapter
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: publicNativePairedCredentials(),
			keys: InMemorySignalKeyStore()
		))
		await client.configureNativeSignalAdapter(
			signalAdapter,
			query: publicNativeDependencyQuery,
			mediaUploader: PublicMediaUploader()
		)

		await #expect(throws: WhatsAppNativeSignalBackendAdapterError.invalidSignedPreKeySignature) {
			try await client.assertNativeMessageReadiness(using: signalAdapter)
		}
		#expect(adapter.signedPreKeySignatureRequests.count == 1)
		#expect(await adapter.accountCheckRequests.isEmpty)
	}

	@Test("native Signal adapter can ensure client message readiness idempotently")
	func nativeSignalAdapterCanEnsureClientMessageReadinessIdempotently() async throws {
		let adapter = PublicNativeSignalAdapter(existingAddresses: [])
		let signalAdapter: any WhatsAppNativeSignalAdapter = adapter
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: publicNativePairedCredentials(),
			keys: InMemorySignalKeyStore()
		))
		await client.configureNativeSignalAdapter(
			signalAdapter,
			query: publicNativeDependencyQuery,
			mediaUploader: PublicMediaUploader()
		)

		let result = try await client.ensureNativeMessageReadiness(using: signalAdapter)

		#expect(result.imported)
		#expect(result.request.localAddress == SignalProtocolAddress(name: "999", deviceID: 0))
		#expect(await adapter.readinessCheckCount == 1)
		#expect(await adapter.accountCheckRequests == [result.request])
		#expect(await adapter.accountImportRequests == [result.request])
	}

	@Test("native Signal adapter ensure readiness rejects invalid credential signing")
	func nativeSignalAdapterEnsureReadinessRejectsInvalidCredentialSigning() async throws {
		let adapter = PublicNativeSignalAdapter(
			existingAddresses: [],
			signedPreKeySignature: Data(repeating: 0x51, count: 63)
		)
		let signalAdapter: any WhatsAppNativeSignalAdapter = adapter
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: publicNativePairedCredentials(),
			keys: InMemorySignalKeyStore()
		))
		await client.configureNativeSignalAdapter(
			signalAdapter,
			query: publicNativeDependencyQuery,
			mediaUploader: PublicMediaUploader()
		)

		await #expect(throws: WhatsAppNativeSignalBackendAdapterError.invalidSignedPreKeySignature) {
			try await client.ensureNativeMessageReadiness(using: signalAdapter)
		}
		#expect(adapter.signedPreKeySignatureRequests.count == 1)
		#expect(await adapter.accountCheckRequests.isEmpty)
		#expect(await adapter.accountImportRequests.isEmpty)
	}

	@Test("native Signal readiness report combines dependencies and account state")
	func nativeSignalReadinessReportCombinesDependenciesAndAccountState() async throws {
		let adapter = PublicNativeSignalAdapter(
			existingAddresses: [],
			existingAccountAddresses: [SignalProtocolAddress(name: "999", deviceID: 0)]
		)
		let signalAdapter: any WhatsAppNativeSignalAdapter = adapter
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: publicNativePairedCredentials(),
			keys: InMemorySignalKeyStore()
		))
		await client.configureNativeSignalAdapter(
			signalAdapter,
			query: publicNativeDependencyQuery,
			mediaUploader: PublicMediaUploader()
		)

		let report = try await client.nativeMessageReadinessReport(using: signalAdapter)

		#expect(report.isReady)
		#expect(report.signalOperationsReadiness == .ready)
		#expect(report.isSignalOperationsReady)
		#expect(report.isNativeAccountImported)
		#expect(report.requiredCapabilities == Set(WhatsAppClientMessageCapability.allCases))
		#expect(report.missingDependencies.isEmpty)
		#expect(report.availableCapabilities == Set(WhatsAppClientMessageCapability.allCases))
		#expect(report.accountRequest.localAddress == SignalProtocolAddress(name: "999", deviceID: 0))
		#expect(report.failures.isEmpty)
		#expect(await adapter.readinessCheckCount == 1)
		#expect(await adapter.accountCheckRequests == [report.accountRequest])
		#expect(await adapter.accountImportRequests.isEmpty)
	}

	@Test("native Signal readiness report marks operation preflight failures")
	func nativeSignalReadinessReportMarksOperationPreflightFailures() async throws {
		let adapter = PublicNativeSignalAdapter(
			existingAddresses: [],
			existingAccountAddresses: [SignalProtocolAddress(name: "999", deviceID: 0)],
			readinessError: NativeSignalReadinessTestError.notReady
		)
		let signalAdapter: any WhatsAppNativeSignalAdapter = adapter
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: publicNativePairedCredentials(),
			keys: InMemorySignalKeyStore()
		))
		await client.configureNativeSignalAdapter(
			signalAdapter,
			query: publicNativeDependencyQuery,
			mediaUploader: PublicMediaUploader()
		)

		let report = try await client.nativeMessageReadinessReport(using: signalAdapter)

		#expect(!report.isReady)
		#expect(report.signalOperationsReadiness == .failed("NativeSignalReadinessTestError"))
		#expect(!report.isSignalOperationsReady)
		#expect(report.signalOperationsReadinessFailure == "NativeSignalReadinessTestError")
		#expect(report.isNativeAccountImported)
		#expect(report.missingDependencies.isEmpty)
		#expect(report.failures == [.signalOperationsFailed("NativeSignalReadinessTestError")])
		#expect(await adapter.readinessCheckCount == 1)
		#expect(await adapter.accountCheckRequests == [report.accountRequest])
		#expect(await adapter.accountImportRequests.isEmpty)
	}

	@Test("native Signal readiness report redacts operation preflight error details")
	func nativeSignalReadinessReportRedactsOperationPreflightErrorDetails() async throws {
		let adapter = PublicNativeSignalAdapter(
			existingAddresses: [],
			existingAccountAddresses: [SignalProtocolAddress(name: "999", deviceID: 0)],
			readinessError: SensitiveNativeSignalReadinessError()
		)
		let signalAdapter: any WhatsAppNativeSignalAdapter = adapter
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: publicNativePairedCredentials(),
			keys: InMemorySignalKeyStore()
		))
		await client.configureNativeSignalAdapter(
			signalAdapter,
			query: publicNativeDependencyQuery,
			mediaUploader: PublicMediaUploader()
		)

		let report = try await client.nativeMessageReadinessReport(using: signalAdapter)

		#expect(report.signalOperationsReadinessFailure == "SensitiveNativeSignalReadinessError")
		#expect(report.signalOperationsReadinessFailure?.contains("private-key-material") == false)
	}

	@Test("native Signal readiness report marks account check failures")
	func nativeSignalReadinessReportMarksAccountCheckFailures() async throws {
		let adapter = PublicNativeSignalAdapter(
			existingAddresses: [],
			existingAccountAddresses: [SignalProtocolAddress(name: "999", deviceID: 0)],
			accountCheckError: SensitiveNativeSignalReadinessError()
		)
		let signalAdapter: any WhatsAppNativeSignalAdapter = adapter
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: publicNativePairedCredentials(),
			keys: InMemorySignalKeyStore()
		))
		await client.configureNativeSignalAdapter(
			signalAdapter,
			query: publicNativeDependencyQuery,
			mediaUploader: PublicMediaUploader()
		)

		let report = try await client.nativeMessageReadinessReport(using: signalAdapter)

		#expect(!report.isReady)
		#expect(report.nativeAccountReadiness == .failed("SensitiveNativeSignalReadinessError"))
		#expect(!report.isNativeAccountImported)
		#expect(report.nativeAccountReadinessFailure == "SensitiveNativeSignalReadinessError")
		#expect(report.nativeAccountReadinessFailure?.contains("private-key-material") == false)
		#expect(report.failures == [.nativeAccountFailed("SensitiveNativeSignalReadinessError")])
	}

	@Test("native Signal readiness report marks credential signing failures")
	func nativeSignalReadinessReportMarksCredentialSigningFailures() async throws {
		let adapter = PublicNativeSignalAdapter(
			existingAddresses: [],
			existingAccountAddresses: [SignalProtocolAddress(name: "999", deviceID: 0)],
			signedPreKeySignature: Data(repeating: 0x51, count: 63)
		)
		let signalAdapter: any WhatsAppNativeSignalAdapter = adapter
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: publicNativePairedCredentials(),
			keys: InMemorySignalKeyStore()
		))
		await client.configureNativeSignalAdapter(
			signalAdapter,
			query: publicNativeDependencyQuery,
			mediaUploader: PublicMediaUploader()
		)

		let report = try await client.nativeMessageReadinessReport(using: signalAdapter)

		#expect(!report.isReady)
		#expect(report.credentialSigningReadiness == .failed("WhatsAppNativeSignalBackendAdapterError"))
		#expect(report.credentialSigningReadinessFailure == "WhatsAppNativeSignalBackendAdapterError")
		#expect(report.failures == [.credentialSigningFailed("WhatsAppNativeSignalBackendAdapterError")])
		#expect(adapter.signedPreKeySignatureRequests.count == 1)
		#expect(adapter.signedPreKeySignatureRequests.first?.signedPreKeyPublicKey.count == 32)
	}

	@Test("native Signal readiness report is side-effect free when setup is incomplete")
	func nativeSignalReadinessReportIsSideEffectFreeWhenSetupIsIncomplete() async throws {
		let adapter = PublicNativeSignalAdapter(existingAddresses: [])
		let signalAdapter: any WhatsAppNativeSignalAdapter = adapter
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: publicNativePairedCredentials(),
			keys: InMemorySignalKeyStore()
		))

		let report = try await client.nativeMessageReadinessReport(
			capabilities: [.directSend, .incomingDecrypt],
			accountChecker: signalAdapter
		)

		#expect(!report.isReady)
		#expect(report.signalOperationsReadiness == .notChecked)
		#expect(!report.isSignalOperationsReady)
		#expect(report.signalOperationsReadinessFailure == "notChecked")
		#expect(!report.isNativeAccountImported)
		#expect(report.requiredCapabilities == [.directSend, .incomingDecrypt])
		#expect(report.availableCapabilities == [.preKeyUpload])
		#expect(report.missingDependencies == [
			.directSend: [
				.messageEncryptor,
				.messageDeviceResolver,
				.signalSessionPreparer
			],
			.incomingDecrypt: [.incomingSignalDecryptor]
		])
		#expect(report.failures == [
			.signalOperationsNotChecked,
			.credentialSigningNotChecked,
			.nativeAccountMissing,
			.missingDependency(.directSend, .messageEncryptor),
			.missingDependency(.directSend, .messageDeviceResolver),
			.missingDependency(.directSend, .signalSessionPreparer),
			.missingDependency(.incomingDecrypt, .incomingSignalDecryptor)
		])
		#expect(await adapter.accountCheckRequests == [report.accountRequest])
		#expect(await adapter.accountImportRequests.isEmpty)
	}

	@Test("account-checker readiness report marks account check failures")
	func accountCheckerReadinessReportMarksAccountCheckFailures() async throws {
		let adapter = PublicNativeSignalAdapter(
			existingAddresses: [],
			accountCheckError: SensitiveNativeSignalReadinessError()
		)
		let signalAdapter: any WhatsAppNativeSignalAdapter = adapter
		let client = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: publicNativePairedCredentials(),
			keys: InMemorySignalKeyStore()
		))

		let report = try await client.nativeMessageReadinessReport(capabilities: [], accountChecker: signalAdapter)

		#expect(!report.isReady)
		#expect(report.signalOperationsReadiness == .notChecked)
		#expect(report.nativeAccountReadiness == .failed("SensitiveNativeSignalReadinessError"))
		#expect(report.nativeAccountReadinessFailure == "SensitiveNativeSignalReadinessError")
		#expect(report.nativeAccountReadinessFailure?.contains("private-key-material") == false)
		#expect(report.failures == [
			.signalOperationsNotChecked,
			.credentialSigningNotChecked,
			.nativeAccountFailed("SensitiveNativeSignalReadinessError")
		])
		#expect(await adapter.accountCheckRequests == [report.accountRequest])
	}

	@Test("native Signal readiness report preserves legacy readiness initializer")
	func nativeSignalReadinessReportPreservesLegacyReadinessInitializer() async throws {
		let request = try publicNativePairedCredentials().nativeAccountImportRequest()

		let report = WhatsAppClientNativeMessageReadinessReport(
			accountRequest: request,
			isSignalOperationsReady: false,
			signalOperationsReadinessFailure: "NativeSignalReadinessTestError",
			isNativeAccountImported: true,
			requiredCapabilities: [.directSend],
			availableCapabilities: [.directSend],
			missingDependencies: [:]
		)

		#expect(report.signalOperationsReadiness == .failed("NativeSignalReadinessTestError"))
		#expect(report.signalOperationsReadinessFailure == "NativeSignalReadinessTestError")
	}
}

private enum NativeSignalReadinessTestError: Error {
	case notReady
}

private struct SensitiveNativeSignalReadinessError: Error, CustomStringConvertible {
	let description = "private-key-material"
}
