import Foundation

public struct AppStatePatchKeySet: Equatable, Sendable {
	public let indexKey: Data
	public let valueEncryptionKey: Data
	public let valueMacKey: Data
	public let snapshotMacKey: Data
	public let patchMacKey: Data

	public init(
		indexKey: Data,
		valueEncryptionKey: Data,
		valueMacKey: Data,
		snapshotMacKey: Data,
		patchMacKey: Data
	) {
		self.indexKey = indexKey
		self.valueEncryptionKey = valueEncryptionKey
		self.valueMacKey = valueMacKey
		self.snapshotMacKey = snapshotMacKey
		self.patchMacKey = patchMacKey
	}
}

struct AppStatePatchIndexValue: Codable, Equatable, Sendable {
	let valueMac: Data
}

struct AppStatePatchState: Codable, Equatable, Sendable {
	var version: UInt64
	var hash: Data
	var indexValueMap: [String: AppStatePatchIndexValue]

	init(version: UInt64 = 0, hash: Data = Data(repeating: 0, count: 128), indexValueMap: [String: AppStatePatchIndexValue] = [:]) {
		self.version = version
		self.hash = hash
		self.indexValueMap = indexValueMap
	}
}

struct AppStatePatchEncodingResult: Equatable, Sendable {
	let patch: Proto_SyncdPatch
	let state: AppStatePatchState
}

public protocol AppStatePatchHashMixing: Sendable {
	func subtractThenAdd(hash: Data, subtract: [Data], add: [Data]) throws -> Data
}

public protocol AppStateKeyExpanding: Sendable {
	func expand(keyData: Data) throws -> AppStatePatchKeySet
}

enum AppStatePatchEncoder {
	static func encode(
		_ patch: ChatModificationPatch,
		keyID: Data,
		keys: AppStatePatchKeySet,
		state initialState: AppStatePatchState,
		randomBytes: @escaping @Sendable (Int) throws -> Data = MessageIDGenerator.secureRandomBytes(count:),
		hashMixer: AppStatePatchHashMixing
	) throws -> AppStatePatchEncodingResult {
		let iv = try randomBytes(16)
		guard iv.count == 16 else {
			throw AppStatePatchEncoderError.invalidIVRandomByteCount
		}

		return try encode(
			patch,
			keyID: keyID,
			keys: keys,
			state: initialState,
			iv: iv,
			hashMixer: hashMixer
		)
	}

	static func encode(
		_ patch: ChatModificationPatch,
		keyID: Data,
		keys: AppStatePatchKeySet,
		state initialState: AppStatePatchState,
		iv: Data,
		hashMixer: AppStatePatchHashMixing
	) throws -> AppStatePatchEncodingResult {
		var state = initialState
		var indexValueMap = state.indexValueMap
		let actionData = try AppStatePatchPayloadBuilder.syncActionData(for: patch)
		let encodedActionData = try actionData.serializedData()
		let encryptedValue = try AppStatePatchCipher.encryptValue(encodedActionData, key: keys.valueEncryptionKey, iv: iv)
		let valueMac = AppStatePatchMAC.valueMac(
			operation: patch.operation,
			encryptedValue: encryptedValue,
			keyID: keyID,
			key: keys.valueMacKey
		)
		let indexMac = AppStatePatchMAC.indexMac(index: actionData.index, key: keys.indexKey)
		let indexKey = indexMac.base64EncodedString()
		let previousValueMac = indexValueMap[indexKey]?.valueMac
		let subtract = previousValueMac.map { [$0] } ?? []
		let add = patch.operation == .remove ? [] : [valueMac]

		if patch.operation == .remove {
			indexValueMap.removeValue(forKey: indexKey)
		} else {
			indexValueMap[indexKey] = AppStatePatchIndexValue(valueMac: valueMac)
		}

		state.hash = try hashMixer.subtractThenAdd(hash: state.hash, subtract: subtract, add: add)
		state.version += 1

		let snapshotMac = AppStatePatchMAC.snapshotMac(
			hash: state.hash,
			version: state.version,
			patchType: patch.type,
			key: keys.snapshotMacKey
		)
		let patchMac = AppStatePatchMAC.patchMac(
			snapshotMac: snapshotMac,
			valueMacs: [valueMac],
			version: state.version,
			patchType: patch.type,
			key: keys.patchMacKey
		)

		var record = Proto_SyncdRecord()
		record.index.blob = indexMac
		record.value.blob = encryptedValue + valueMac
		record.keyID.id = keyID
		var mutation = Proto_SyncdMutation()
		mutation.operation = patch.operation == .set ? .set : .remove
		mutation.record = record
		var syncdPatch = Proto_SyncdPatch()
		syncdPatch.patchMac = patchMac
		syncdPatch.snapshotMac = snapshotMac
		syncdPatch.keyID.id = keyID
		syncdPatch.mutations = [mutation]
		indexValueMap[indexKey] = AppStatePatchIndexValue(valueMac: valueMac)
		state.indexValueMap = indexValueMap

		return AppStatePatchEncodingResult(patch: syncdPatch, state: state)
	}
}

enum AppStatePatchEncoderError: Error, Equatable, Sendable {
	case invalidIVRandomByteCount
}
