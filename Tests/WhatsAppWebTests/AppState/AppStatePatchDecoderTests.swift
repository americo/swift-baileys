import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("App-state patch decoder")
struct AppStatePatchDecoderTests {
	@Test("decodes patches into the next collection state")
	func decodesPatchesIntoTheNextCollectionState() async throws {
		let keys = try appStateFixtureKeys()
		let encoded = try AppStatePatchEncoder.encode(
			ChatModificationPatchBuilder.patch(for: .pin(jid: "123@s.whatsapp.net", pinned: true)),
			keyID: try appStateHexData("0102030405060708"),
			keys: keys,
			state: AppStatePatchState(),
			iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)
		var patch = encoded.patch
		patch.version.version = encoded.state.version

		let result = try await AppStatePatchDecoder.decode(
			patch,
			collection: .regularLow,
			initialState: AppStatePatchState(),
			keyResolver: { _ in keys },
			hashMixer: NativeAppStatePatchHashMixer()
		)

		#expect(result.state == encoded.state)
		#expect(result.mutations.first?.index == ["pin_v1", "123@s.whatsapp.net"])
	}

	@Test("rejects invalid patch MACs")
	func rejectsInvalidPatchMACs() async throws {
		let keys = try appStateFixtureKeys()
		let encoded = try AppStatePatchEncoder.encode(
			ChatModificationPatchBuilder.patch(for: .pin(jid: "123@s.whatsapp.net", pinned: true)),
			keyID: try appStateHexData("0102030405060708"),
			keys: keys,
			state: AppStatePatchState(),
			iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)
		var patch = encoded.patch
		patch.version.version = encoded.state.version
		patch.patchMac = Data(repeating: 0, count: 32)

		await #expect(throws: AppStatePatchDecoderError.invalidPatchMAC) {
			try await AppStatePatchDecoder.decode(
				patch,
				collection: .regularLow,
				initialState: AppStatePatchState(),
				keyResolver: { _ in keys },
				hashMixer: NativeAppStatePatchHashMixer()
			)
		}
	}

	@Test("downloads external mutations before validating patch MAC")
	func downloadsExternalMutationsBeforeValidatingPatchMAC() async throws {
		let keys = try appStateFixtureKeys()
		let encoded = try AppStatePatchEncoder.encode(
			ChatModificationPatchBuilder.patch(for: .pin(jid: "123@s.whatsapp.net", pinned: true)),
			keyID: try appStateHexData("0102030405060708"),
			keys: keys,
			state: AppStatePatchState(),
			iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
			hashMixer: NativeAppStatePatchHashMixer()
		)
		var externalMutations = Proto_SyncdMutations()
		externalMutations.mutations = encoded.patch.mutations
		var blob = Proto_ExternalBlobReference()
		blob.directPath = "/mms/md-app-state/patch"
		var patch = encoded.patch
		patch.version.version = encoded.state.version
		patch.mutations = []
		patch.externalMutations = blob
		let downloader = RecordingPatchBlobDownloader(data: try externalMutations.serializedData())

		let result = try await AppStatePatchDecoder.decode(
			patch,
			collection: .regularLow,
			initialState: AppStatePatchState(),
			keyResolver: { _ in keys },
			hashMixer: NativeAppStatePatchHashMixer(),
			downloadExternalBlob: downloader.download(_:)
		)

		#expect(result.state == encoded.state)
		#expect(result.mutations.first?.index == ["pin_v1", "123@s.whatsapp.net"])
		#expect(await downloader.directPaths == ["/mms/md-app-state/patch"])
	}
}

private actor RecordingPatchBlobDownloader {
	private let data: Data
	private var paths: [String] = []

	init(data: Data) {
		self.data = data
	}

	var directPaths: [String] {
		paths
	}

	func download(_ reference: Proto_ExternalBlobReference) async throws -> Data {
		paths.append(reference.directPath)
		return data
	}
}
