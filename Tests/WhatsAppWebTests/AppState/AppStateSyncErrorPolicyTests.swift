import Testing
@testable import WhatsAppWeb

@Suite("App-state sync error policy")
struct AppStateSyncErrorPolicyTests {
	@Test("classifies decoder missing-key errors")
	func classifiesDecoderMissingKeyErrors() {
		#expect(AppStateSyncErrorPolicy.isMissingKey(AppStatePatchDecoderError.missingKey("AQID")))
		#expect(AppStateSyncErrorPolicy.isMissingKey(AppStateSnapshotDecoderError.missingKey("AQID")))
		#expect(AppStateSyncErrorPolicy.isMissingKey(AppStateMutationDecoderError.missingKey("AQID")))
	}

	@Test("does not classify non-key decoder errors as missing keys")
	func doesNotClassifyNonKeyDecoderErrorsAsMissingKeys() {
		#expect(!AppStateSyncErrorPolicy.isMissingKey(AppStatePatchDecoderError.invalidPatchMAC))
		#expect(!AppStateSyncErrorPolicy.isMissingKey(AppStateSnapshotDecoderError.missingSnapshotVersion))
		#expect(!AppStateSyncErrorPolicy.isMissingKey(AppStateMutationDecoderError.invalidIndexMAC))
	}

	@Test("treats two attempts or type errors as irrecoverable")
	func treatsTwoAttemptsOrTypeErrorsAsIrrecoverable() {
		#expect(!AppStateSyncErrorPolicy.isIrrecoverable(attempts: 0))
		#expect(!AppStateSyncErrorPolicy.isIrrecoverable(attempts: 1))
		#expect(AppStateSyncErrorPolicy.isIrrecoverable(attempts: AppStateSyncErrorPolicy.maxSyncAttempts))
		#expect(AppStateSyncErrorPolicy.isIrrecoverable(attempts: 0, errorIsTypeError: true))
	}
}
