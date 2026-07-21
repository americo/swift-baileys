import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("App-state mutation decoder")
struct AppStateMutationDecoderTests {
	@Test("decodes set mutations and updates LTHash state")
	func decodesSetMutationsAndUpdatesLTHashState() async throws {
		let keys = try appStateFixtureKeys()
		let patch = ChatModificationPatchBuilder.patch(for: .pin(jid: "123@s.whatsapp.net", pinned: true))
		let encoded = try AppStatePatchEncoder.encode(
			patch,
			keyID: try appStateHexData("0102030405060708"),
			keys: keys,
			state: AppStatePatchState(),
			iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)

		let result = try await AppStateMutationDecoder.decode(
			encoded.patch.mutations,
			initialState: AppStatePatchState(),
			keyResolver: { _ in keys },
			hashMixer: NativeAppStatePatchHashMixer()
		)

		let mutation = try #require(result.mutations.first)
		#expect(result.mutations.count == 1)
		#expect(mutation.index == ["pin_v1", "123@s.whatsapp.net"])
		#expect(mutation.syncAction.value.hasPinAction)
		#expect(result.hash == encoded.state.hash)
		#expect(result.indexValueMap == encoded.state.indexValueMap)
	}

	@Test("decodes remove mutations by subtracting the previous value MAC")
	func decodesRemoveMutationsBySubtractingPreviousValueMAC() async throws {
		let keys = try appStateFixtureKeys()
		let setPatch = ChatModificationPatchBuilder.patch(for: .contact(
			jid: "123@s.whatsapp.net",
			contact: ChatModificationContact(fullName: "A")
		))
		let set = try AppStatePatchEncoder.encode(
			setPatch,
			keyID: try appStateHexData("0102030405060708"),
			keys: keys,
			state: AppStatePatchState(),
			iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)
		let removePatch = ChatModificationPatchBuilder.patch(for: .contact(jid: "123@s.whatsapp.net", contact: nil))
		let remove = try AppStatePatchEncoder.encode(
			removePatch,
			keyID: try appStateHexData("0102030405060708"),
			keys: keys,
			state: set.state,
			iv: try appStateHexData("303132333435363738393a3b3c3d3e3f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)

		let result = try await AppStateMutationDecoder.decode(
			remove.patch.mutations,
			initialState: set.state,
			keyResolver: { _ in keys },
			hashMixer: NativeAppStatePatchHashMixer()
		)

		let mutation = try #require(result.mutations.first)
		#expect(mutation.index == ["contact", "123@s.whatsapp.net"])
		#expect(result.hash == remove.state.hash)
		#expect(result.indexValueMap["ToDeP6PyaSeZnm9YDJhQ0SoD4tV62Lx+2Yc2eR1Sh80="] == nil)
	}

	@Test("propagates missing app-state keys")
	func propagatesMissingAppStateKeys() async throws {
		let keys = try appStateFixtureKeys()
		let encoded = try AppStatePatchEncoder.encode(
			ChatModificationPatchBuilder.patch(for: .pin(jid: "123@s.whatsapp.net", pinned: true)),
			keyID: try appStateHexData("0102030405060708"),
			keys: keys,
			state: AppStatePatchState(),
			iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)

		await #expect(throws: AppStateMutationDecoderError.missingKey("AQIDBAUGBwg=")) {
			try await AppStateMutationDecoder.decode(
				encoded.patch.mutations,
				initialState: AppStatePatchState(),
				keyResolver: { _ in nil },
				hashMixer: NativeAppStatePatchHashMixer()
			)
		}
	}

	@Test("skips records with invalid value MACs")
	func skipsRecordsWithInvalidValueMACs() async throws {
		let keys = try appStateFixtureKeys()
		let encoded = try AppStatePatchEncoder.encode(
			ChatModificationPatchBuilder.patch(for: .pin(jid: "123@s.whatsapp.net", pinned: true)),
			keyID: try appStateHexData("0102030405060708"),
			keys: keys,
			state: AppStatePatchState(),
			iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)
		var mutation = try #require(encoded.patch.mutations.first)
		var blob = mutation.record.value.blob
		blob[blob.count - 1] ^= 0xff
		mutation.record.value.blob = blob

		let result = try await AppStateMutationDecoder.decode(
			[mutation],
			initialState: AppStatePatchState(),
			keyResolver: { _ in keys },
			hashMixer: NativeAppStatePatchHashMixer()
		)

		#expect(result.mutations.isEmpty)
		#expect(result.hash == Data(repeating: 0, count: 128))
		#expect(result.indexValueMap.isEmpty)
	}
}

func appStateFixtureKeys() throws -> AppStatePatchKeySet {
	AppStatePatchKeySet(
		indexKey: try appStateHexData("61387bcf643616a68bd611a45516b3980418323087d78bf08c615645549434b4"),
		valueEncryptionKey: try appStateHexData("900ba2843ba5fb0cee55cf2a4de9503dce68187d3f6b95b420b008bde66f5a20"),
		valueMacKey: try appStateHexData("d0879f6b61f0bcba79faad3f47a8a768fd7fc04a6cc8b3ecefedfa087413226f"),
		snapshotMacKey: try appStateHexData("69b2e91be6587307c43c29b027a71fdd55be25f07ca726714115430d23093071"),
		patchMacKey: try appStateHexData("693845bdd996652aca9ca0b96d0f081abf29943303c5eb19bdb84f38b24c32ab")
	)
}

func appStateHexData(_ hexString: String) throws -> Data {
	guard hexString.count.isMultiple(of: 2) else {
		throw AppStateHexDataError.invalidLength
	}

	var bytes = [UInt8]()
	bytes.reserveCapacity(hexString.count / 2)
	var index = hexString.startIndex
	while index < hexString.endIndex {
		let next = hexString.index(index, offsetBy: 2)
		guard let byte = UInt8(hexString[index..<next], radix: 16) else {
			throw AppStateHexDataError.invalidByte
		}
		bytes.append(byte)
		index = next
	}
	return Data(bytes)
}

enum AppStateHexDataError: Error {
	case invalidLength
	case invalidByte
}
