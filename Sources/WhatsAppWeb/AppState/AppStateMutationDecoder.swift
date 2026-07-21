import Foundation

typealias AppStatePatchKeyResolver = (String) async throws -> AppStatePatchKeySet?

struct AppStateDecodedMutation: Equatable, Sendable {
	let syncAction: Proto_SyncActionData
	let index: [String]
}

struct AppStateMutationDecodeResult: Equatable, Sendable {
	let hash: Data
	let indexValueMap: [String: AppStatePatchIndexValue]
	let mutations: [AppStateDecodedMutation]
}

enum AppStateMutationDecoderError: Error, Equatable, Sendable {
	case missingRecord
	case missingRecordKeyID
	case missingKey(String)
	case malformedRecordValue
	case invalidIndexJSON
	case invalidIndexMAC
}

enum AppStateMutationDecoder {
	static func decode(
		_ mutations: [Proto_SyncdMutation],
		initialState: AppStatePatchState,
		keyResolver: AppStatePatchKeyResolver,
		hashMixer: AppStatePatchHashMixing,
		validateMACs: Bool = true
	) async throws -> AppStateMutationDecodeResult {
		var indexValueMap = initialState.indexValueMap
		var decoded: [AppStateDecodedMutation] = []
		var add: [Data] = []
		var subtract: [Data] = []

		for mutation in mutations {
			guard mutation.hasRecord else {
				throw AppStateMutationDecoderError.missingRecord
			}

			let operation: ChatModificationPatchOperation = mutation.operation == .remove ? .remove : .set
			let record = mutation.record
			guard record.hasKeyID else {
				throw AppStateMutationDecoderError.missingRecordKeyID
			}

			let keyID = record.keyID.id
			let base64KeyID = keyID.base64EncodedString()
			guard let keys = try await keyResolver(base64KeyID) else {
				throw AppStateMutationDecoderError.missingKey(base64KeyID)
			}
			guard record.value.blob.count >= 32 else {
				throw AppStateMutationDecoderError.malformedRecordValue
			}

			let encryptedValue = Data(record.value.blob.dropLast(32))
			let valueMac = Data(record.value.blob.suffix(32))
			if validateMACs {
				let expectedValueMac = AppStatePatchMAC.valueMac(
					operation: operation,
					encryptedValue: encryptedValue,
					keyID: keyID,
					key: keys.valueMacKey
				)
				if expectedValueMac != valueMac {
					continue
				}
			}

			let plaintext: Data
			do {
				plaintext = try AppStatePatchCipher.decryptValue(encryptedValue, key: keys.valueEncryptionKey)
			} catch {
				continue
			}

			let syncAction = try Proto_SyncActionData(serializedBytes: plaintext)
			if validateMACs, AppStatePatchMAC.indexMac(index: syncAction.index, key: keys.indexKey) != record.index.blob {
				throw AppStateMutationDecoderError.invalidIndexMAC
			}

			let rawIndex = try JSONSerialization.jsonObject(with: syncAction.index)
			guard let index = rawIndex as? [String] else {
				throw AppStateMutationDecoderError.invalidIndexJSON
			}

			decoded.append(AppStateDecodedMutation(syncAction: syncAction, index: index))
			let indexKey = record.index.blob.base64EncodedString()
			let previousValueMac = indexValueMap[indexKey]?.valueMac
			if operation == .remove {
				if previousValueMac == nil {
					continue
				}
				indexValueMap.removeValue(forKey: indexKey)
			} else {
				add.append(valueMac)
				indexValueMap[indexKey] = AppStatePatchIndexValue(valueMac: valueMac)
			}
			if let previousValueMac {
				subtract.append(previousValueMac)
			}
		}

		let hash = try hashMixer.subtractThenAdd(hash: initialState.hash, subtract: subtract, add: add)
		return AppStateMutationDecodeResult(hash: hash, indexValueMap: indexValueMap, mutations: decoded)
	}
}
