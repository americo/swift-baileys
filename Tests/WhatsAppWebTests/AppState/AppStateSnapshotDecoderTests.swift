import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("App-state snapshot decoder")
struct AppStateSnapshotDecoderTests {
	@Test("decodes snapshot records into collection state")
	func decodesSnapshotRecordsIntoCollectionState() async throws {
		let keys = try appStateFixtureKeys()
		let encoded = try AppStatePatchEncoder.encode(
			ChatModificationPatchBuilder.patch(for: .pin(jid: "123@s.whatsapp.net", pinned: true)),
			keyID: try appStateHexData("0102030405060708"),
			keys: keys,
			state: AppStatePatchState(),
			iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)
		var snapshot = Proto_SyncdSnapshot()
		snapshot.version.version = encoded.state.version
		snapshot.records = encoded.patch.mutations.map(\.record)
		snapshot.mac = encoded.patch.snapshotMac
		snapshot.keyID = encoded.patch.keyID

		let result = try await AppStateSnapshotDecoder.decode(
			snapshot,
			collection: .regularLow,
			keyResolver: { _ in keys },
			hashMixer: NativeAppStatePatchHashMixer()
		)

		#expect(result.state == encoded.state)
		#expect(result.mutations.first?.index == ["pin_v1", "123@s.whatsapp.net"])
		#expect(result.snapshotMACValid)
	}

	@Test("continues with partial state when snapshot MAC does not match")
	func continuesWithPartialStateWhenSnapshotMACDoesNotMatch() async throws {
		let keys = try appStateFixtureKeys()
		let encoded = try AppStatePatchEncoder.encode(
			ChatModificationPatchBuilder.patch(for: .pin(jid: "123@s.whatsapp.net", pinned: true)),
			keyID: try appStateHexData("0102030405060708"),
			keys: keys,
			state: AppStatePatchState(),
			iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)
		var snapshot = Proto_SyncdSnapshot()
		snapshot.version.version = encoded.state.version
		snapshot.records = encoded.patch.mutations.map(\.record)
		snapshot.mac = Data(repeating: 0, count: 32)
		snapshot.keyID = encoded.patch.keyID

		let result = try await AppStateSnapshotDecoder.decode(
			snapshot,
			collection: .regularLow,
			keyResolver: { _ in keys },
			hashMixer: NativeAppStatePatchHashMixer()
		)

		#expect(result.state == encoded.state)
		#expect(result.snapshotMACValid == false)
	}
}
