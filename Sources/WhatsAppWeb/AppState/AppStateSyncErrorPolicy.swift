enum AppStateSyncErrorPolicy {
	static let maxSyncAttempts = 2

	static func isMissingKey(_ error: any Error) -> Bool {
		if case .missingKey = error as? AppStatePatchDecoderError {
			return true
		}
		if case .missingKey = error as? AppStateSnapshotDecoderError {
			return true
		}
		if case .missingKey = error as? AppStateMutationDecoderError {
			return true
		}

		return false
	}

	static func isIrrecoverable(attempts: Int, errorIsTypeError: Bool = false) -> Bool {
		attempts >= maxSyncAttempts || errorIsTypeError
	}
}
