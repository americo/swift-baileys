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

	/// The base64 id of the key the error says is missing.
	static func missingKeyID(_ error: any Error) -> String? {
		if case .missingKey(let id) = error as? AppStatePatchDecoderError {
			return id
		}
		if case .missingKey(let id) = error as? AppStateSnapshotDecoderError {
			return id
		}
		if case .missingKey(let id) = error as? AppStateMutationDecoderError {
			return id
		}

		return nil
	}

	static func isIrrecoverable(attempts: Int, errorIsTypeError: Bool = false) -> Bool {
		attempts >= maxSyncAttempts || errorIsTypeError
	}
}
