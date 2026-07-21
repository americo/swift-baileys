import Foundation

struct AppStatePatchDecodeResult: Equatable, Sendable {
	let state: AppStatePatchState
	let mutations: [AppStateDecodedMutation]
}

enum AppStatePatchDecoderError: Error, Equatable, Sendable {
	case missingPatchKeyID
	case missingPatchVersion
	case missingKey(String)
	case missingExternalMutationsDownloader
	case invalidPatchMAC
}

enum AppStatePatchDecoder {
	static func decode(
		_ patch: Proto_SyncdPatch,
		collection: AppStateCollectionName,
		initialState: AppStatePatchState,
		keyResolver: AppStatePatchKeyResolver,
		hashMixer: AppStatePatchHashMixing,
		downloadExternalBlob: AppStateExternalBlobDownloader? = nil,
		validateMACs: Bool = true
	) async throws -> AppStatePatchDecodeResult {
		var patch = patch
		guard patch.hasVersion else {
			throw AppStatePatchDecoderError.missingPatchVersion
		}
		if patch.hasExternalMutations {
			guard let downloadExternalBlob else {
				throw AppStatePatchDecoderError.missingExternalMutationsDownloader
			}
			let data = try await downloadExternalBlob(patch.externalMutations)
			patch.mutations.append(contentsOf: try Proto_SyncdMutations(serializedBytes: data).mutations)
		}

		if validateMACs {
			guard patch.hasKeyID else {
				throw AppStatePatchDecoderError.missingPatchKeyID
			}
			let base64KeyID = patch.keyID.id.base64EncodedString()
			guard let keys = try await keyResolver(base64KeyID) else {
				throw AppStatePatchDecoderError.missingKey(base64KeyID)
			}
			let valueMacs = patch.mutations.compactMap { mutation -> Data? in
				guard mutation.record.value.blob.count >= 32 else {
					return nil
				}
				return Data(mutation.record.value.blob.suffix(32))
			}
			let expectedPatchMac = AppStatePatchMAC.patchMac(
				snapshotMac: patch.snapshotMac,
				valueMacs: valueMacs,
				version: patch.version.version,
				patchType: collection.patchType,
				key: keys.patchMacKey
			)
			guard expectedPatchMac == patch.patchMac else {
				throw AppStatePatchDecoderError.invalidPatchMAC
			}
		}

		let decoded = try await AppStateMutationDecoder.decode(
			patch.mutations,
			initialState: initialState,
			keyResolver: keyResolver,
			hashMixer: hashMixer,
			validateMACs: validateMACs
		)
		let state = AppStatePatchState(
			version: patch.version.version,
			hash: decoded.hash,
			indexValueMap: decoded.indexValueMap
		)
		return AppStatePatchDecodeResult(state: state, mutations: decoded.mutations)
	}
}
