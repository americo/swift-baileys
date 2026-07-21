import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("App-state patch encoder")
struct AppStatePatchEncoderTests {
	@Test("assembles syncd patch with encrypted value and MACs")
	func assemblesSyncdPatchWithEncryptedValueAndMACs() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .pin(jid: "123@s.whatsapp.net", pinned: true))
		let mixer = RecordingHashMixer(result: Data(repeating: 9, count: 128))

		let result = try AppStatePatchEncoder.encode(
			patch,
			keyID: try Data(hexString: "0102030405060708"),
			keys: AppStatePatchKeySet(
				indexKey: try Data(hexString: "61387bcf643616a68bd611a45516b3980418323087d78bf08c615645549434b4"),
				valueEncryptionKey: try Data(hexString: "900ba2843ba5fb0cee55cf2a4de9503dce68187d3f6b95b420b008bde66f5a20"),
				valueMacKey: try Data(hexString: "d0879f6b61f0bcba79faad3f47a8a768fd7fc04a6cc8b3ecefedfa087413226f"),
				snapshotMacKey: try Data(hexString: "69b2e91be6587307c43c29b027a71fdd55be25f07ca726714115430d23093071"),
				patchMacKey: try Data(hexString: "693845bdd996652aca9ca0b96d0f081abf29943303c5eb19bdb84f38b24c32ab")
			),
			state: AppStatePatchState(),
			iv: try Data(hexString: "202122232425262728292a2b2c2d2e2f"),
			hashMixer: mixer
		)

		#expect(mixer.calls == [
			HashMixerCall(
				hash: Data(repeating: 0, count: 128),
				subtract: [],
				add: [try Data(hexString: "c520416b5f20f9f4cdc636fdea62a1f6582d2f4a881f023bca53a451575d1789")]
			)
		])
		#expect(result.state.version == 1)
		#expect(result.state.hash == Data(repeating: 9, count: 128))
		#expect(result.state.indexValueMap["pIqsg6sbEkmeAWPympcYu9Pmr0fGG+AhIbCHDv/pc5Y="]?.valueMac == (try Data(hexString: "c520416b5f20f9f4cdc636fdea62a1f6582d2f4a881f023bca53a451575d1789")))
		#expect(result.patch.keyID.id == (try Data(hexString: "0102030405060708")))
		#expect(result.patch.snapshotMac == (try Data(hexString: "044528f72fdbbda6368b09fad2cc35c14995940d53d03bbea9a9d686b28a4ac0")))
		#expect(result.patch.patchMac == (try Data(hexString: "a4d9a2c4c9c8fb9d55cabbc044d70e08a59f645433d8d469c759f78cd435867a")))
		#expect(result.patch.mutations.count == 1)
		let mutation = try #require(result.patch.mutations.first)
		#expect(mutation.operation == .set)
		#expect(mutation.record.index.blob == (try Data(hexString: "a48aac83ab1b12499e0163f29a9718bbd3e6af47c61be02121b0870effe97396")))
		#expect(mutation.record.value.blob == (try Data(hexString: "202122232425262728292a2b2c2d2e2f768dca08829136cb6e3cbcd62cd1cccaf5ca91f0505c34ec2da2f52d21b33c1c936ee82bc825d6ee3b0fb3e4239324afc520416b5f20f9f4cdc636fdea62a1f6582d2f4a881f023bca53a451575d1789")))
		#expect(mutation.record.keyID.id == (try Data(hexString: "0102030405060708")))
	}

	@Test("removes previous value MACs from the hash state")
	func removesPreviousValueMACsFromTheHashState() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .contact(jid: "123@s.whatsapp.net", contact: nil))
		let indexKey = try Data(hexString: "61387bcf643616a68bd611a45516b3980418323087d78bf08c615645549434b4")
		let actionData = try AppStatePatchPayloadBuilder.syncActionData(for: patch)
		let indexStateKey = AppStatePatchMAC.indexMac(index: actionData.index, key: indexKey).base64EncodedString()
		let previousValueMac = Data(repeating: 7, count: 32)
		let mixer = RecordingHashMixer(result: Data(repeating: 8, count: 128))

		let result = try AppStatePatchEncoder.encode(
			patch,
			keyID: try Data(hexString: "0102030405060708"),
			keys: AppStatePatchKeySet(
				indexKey: indexKey,
				valueEncryptionKey: try Data(hexString: "900ba2843ba5fb0cee55cf2a4de9503dce68187d3f6b95b420b008bde66f5a20"),
				valueMacKey: try Data(hexString: "d0879f6b61f0bcba79faad3f47a8a768fd7fc04a6cc8b3ecefedfa087413226f"),
				snapshotMacKey: try Data(hexString: "69b2e91be6587307c43c29b027a71fdd55be25f07ca726714115430d23093071"),
				patchMacKey: try Data(hexString: "693845bdd996652aca9ca0b96d0f081abf29943303c5eb19bdb84f38b24c32ab")
			),
			state: AppStatePatchState(
				version: 2,
				hash: Data(repeating: 6, count: 128),
				indexValueMap: [indexStateKey: AppStatePatchIndexValue(valueMac: previousValueMac)]
			),
			iv: try Data(hexString: "202122232425262728292a2b2c2d2e2f"),
			hashMixer: mixer
		)

		#expect(mixer.calls.count == 1)
		let call = try #require(mixer.calls.first)
		#expect(call.hash == Data(repeating: 6, count: 128))
		#expect(call.subtract == [previousValueMac])
		#expect(call.add.isEmpty)
		#expect(result.state.version == 3)
		#expect(result.state.hash == Data(repeating: 8, count: 128))
		#expect(result.state.indexValueMap[indexStateKey]?.valueMac != nil)
		#expect(result.state.indexValueMap[indexStateKey]?.valueMac != previousValueMac)
		#expect(result.patch.mutations.first?.operation == .remove)
	}

	@Test("generates a 16-byte IV for production encoding")
	func generates16ByteIVForProductionEncoding() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .pin(jid: "123@s.whatsapp.net", pinned: true))
		let random = RecordingRandomBytes(result: try Data(hexString: "202122232425262728292a2b2c2d2e2f"))

		let result = try AppStatePatchEncoder.encode(
			patch,
			keyID: try Data(hexString: "0102030405060708"),
			keys: fixtureKeys(),
			state: AppStatePatchState(),
			randomBytes: random.bytes(count:),
			hashMixer: RecordingHashMixer(result: Data(repeating: 9, count: 128))
		)

		#expect(random.counts == [16])
		#expect(result.patch.mutations.first?.record.value.blob == (try Data(hexString: "202122232425262728292a2b2c2d2e2f768dca08829136cb6e3cbcd62cd1cccaf5ca91f0505c34ec2da2f52d21b33c1c936ee82bc825d6ee3b0fb3e4239324afc520416b5f20f9f4cdc636fdea62a1f6582d2f4a881f023bca53a451575d1789")))
	}

	@Test("rejects invalid generated IV lengths")
	func rejectsInvalidGeneratedIVLengths() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .pin(jid: "123@s.whatsapp.net", pinned: true))

		#expect(throws: AppStatePatchEncoderError.invalidIVRandomByteCount) {
			try AppStatePatchEncoder.encode(
				patch,
				keyID: try Data(hexString: "0102030405060708"),
				keys: fixtureKeys(),
				state: AppStatePatchState(),
				randomBytes: { _ in Data(repeating: 0, count: 15) },
				hashMixer: RecordingHashMixer(result: Data(repeating: 9, count: 128))
			)
		}
	}

	private func fixtureKeys() throws -> AppStatePatchKeySet {
		AppStatePatchKeySet(
			indexKey: try Data(hexString: "61387bcf643616a68bd611a45516b3980418323087d78bf08c615645549434b4"),
			valueEncryptionKey: try Data(hexString: "900ba2843ba5fb0cee55cf2a4de9503dce68187d3f6b95b420b008bde66f5a20"),
			valueMacKey: try Data(hexString: "d0879f6b61f0bcba79faad3f47a8a768fd7fc04a6cc8b3ecefedfa087413226f"),
			snapshotMacKey: try Data(hexString: "69b2e91be6587307c43c29b027a71fdd55be25f07ca726714115430d23093071"),
			patchMacKey: try Data(hexString: "693845bdd996652aca9ca0b96d0f081abf29943303c5eb19bdb84f38b24c32ab")
		)
	}
}

private struct HashMixerCall: Equatable {
	let hash: Data
	let subtract: [Data]
	let add: [Data]
}

private final class RecordingHashMixer: AppStatePatchHashMixing, @unchecked Sendable {
	private(set) var calls: [HashMixerCall] = []
	private let result: Data

	init(result: Data) {
		self.result = result
	}

	func subtractThenAdd(hash: Data, subtract: [Data], add: [Data]) throws -> Data {
		calls.append(HashMixerCall(hash: hash, subtract: subtract, add: add))
		return result
	}
}

private final class RecordingRandomBytes: @unchecked Sendable {
	private(set) var counts: [Int] = []
	private let result: Data

	init(result: Data) {
		self.result = result
	}

	func bytes(count: Int) -> Data {
		counts.append(count)
		return result
	}
}

private extension Data {
	init(hexString: String) throws {
		guard hexString.count.isMultiple(of: 2) else {
			throw HexDataError.invalidLength
		}

		var bytes = [UInt8]()
		bytes.reserveCapacity(hexString.count / 2)
		var index = hexString.startIndex
		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw HexDataError.invalidByte
			}
			bytes.append(byte)
			index = next
		}
		self = Data(bytes)
	}
}

private enum HexDataError: Error {
	case invalidLength
	case invalidByte
}
