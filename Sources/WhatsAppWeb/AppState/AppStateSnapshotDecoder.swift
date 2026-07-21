import Foundation

struct AppStateSnapshotDecodeResult: Equatable, Sendable {
	let state: AppStatePatchState
	let mutations: [AppStateDecodedMutation]
	let snapshotMACValid: Bool
}

enum AppStateSnapshotDecoderError: Error, Equatable, Sendable {
	case missingSnapshotVersion
	case missingSnapshotKeyID
	case missingKey(String)
}

enum AppStateSnapshotDecoder {
	static func decode(
		_ snapshot: Proto_SyncdSnapshot,
		collection: AppStateCollectionName,
		keyResolver: AppStatePatchKeyResolver,
		hashMixer: AppStatePatchHashMixing,
		validateMACs: Bool = true
	) async throws -> AppStateSnapshotDecodeResult {
		guard snapshot.hasVersion else {
			throw AppStateSnapshotDecoderError.missingSnapshotVersion
		}

		let mutations = snapshot.records.map { record in
			var mutation = Proto_SyncdMutation()
			mutation.operation = .set
			mutation.record = record
			return mutation
		}
		let decoded = try await AppStateMutationDecoder.decode(
			mutations,
			initialState: AppStatePatchState(version: snapshot.version.version),
			keyResolver: keyResolver,
			hashMixer: hashMixer,
			validateMACs: validateMACs
		)
		let state = AppStatePatchState(
			version: snapshot.version.version,
			hash: decoded.hash,
			indexValueMap: decoded.indexValueMap
		)

		var snapshotMACValid = true
		if validateMACs {
			guard snapshot.hasKeyID else {
				throw AppStateSnapshotDecoderError.missingSnapshotKeyID
			}
			let base64KeyID = snapshot.keyID.id.base64EncodedString()
			guard let keys = try await keyResolver(base64KeyID) else {
				throw AppStateSnapshotDecoderError.missingKey(base64KeyID)
			}
			let expectedSnapshotMac = AppStatePatchMAC.snapshotMac(
				hash: state.hash,
				version: state.version,
				patchType: collection.patchType,
				key: keys.snapshotMacKey
			)
			snapshotMACValid = expectedSnapshotMac == snapshot.mac
		}

		return AppStateSnapshotDecodeResult(
			state: state,
			mutations: decoded.mutations,
			snapshotMACValid: snapshotMACValid
		)
	}
}
