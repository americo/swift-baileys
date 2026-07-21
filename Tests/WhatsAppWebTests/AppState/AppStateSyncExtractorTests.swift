import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("App-state sync extractor")
struct AppStateSyncExtractorTests {
	@Test("extracts patches and fills absent patch versions from the collection")
	func extractsPatchesAndFillsAbsentPatchVersionsFromTheCollection() async throws {
		var patch = Proto_SyncdPatch()
		patch.patchMac = Data([1])
		patch.snapshotMac = Data([2])

		let result = BinaryNode(tag: "iq", content: .nodes([
			BinaryNode(tag: "sync", content: .nodes([
				BinaryNode(
					tag: "collection",
					attrs: ["name": "regular_low", "version": "3", "has_more_patches": "true"],
					content: .nodes([
						BinaryNode(tag: "patches", content: .nodes([
							BinaryNode(tag: "patch", content: .data(try patch.serializedData()))
						]))
					])
				)
			]))
		]))

		let collections = try await AppStateSyncExtractor.extract(from: result)
		let collection = try #require(collections["regular_low"])
		#expect(collection.name == "regular_low")
		#expect(collection.hasMorePatches)
		#expect(collection.patches.count == 1)
		#expect(collection.patches.first?.version.version == 4)
		#expect(collection.snapshot == nil)
	}

	@Test("preserves explicit patch versions")
	func preservesExplicitPatchVersions() async throws {
		var version = Proto_SyncdVersion()
		version.version = 9
		var patch = Proto_SyncdPatch()
		patch.version = version

		let result = BinaryNode(tag: "iq", content: .nodes([
			BinaryNode(tag: "sync", content: .nodes([
				BinaryNode(
					tag: "collection",
					attrs: ["name": "regular", "version": "3"],
					content: .nodes([
						BinaryNode(tag: "patch", content: .data(try patch.serializedData()))
					])
				)
			]))
		]))

		let collection = try #require(try await AppStateSyncExtractor.extract(from: result)["regular"])
		#expect(collection.hasMorePatches == false)
		#expect(collection.patches.first?.version.version == 9)
	}

	@Test("downloads and decodes snapshot blobs")
	func downloadsAndDecodesSnapshotBlobs() async throws {
		var snapshotVersion = Proto_SyncdVersion()
		snapshotVersion.version = 7
		var snapshot = Proto_SyncdSnapshot()
		snapshot.version = snapshotVersion
		snapshot.mac = Data([4, 5])

		var blob = Proto_ExternalBlobReference()
		blob.directPath = "/mms/md-app-state/test"
		let downloader = RecordingAppStateBlobDownloader(data: try snapshot.serializedData())
		let result = BinaryNode(tag: "iq", content: .nodes([
			BinaryNode(tag: "sync", content: .nodes([
				BinaryNode(
					tag: "collection",
					attrs: ["name": "critical_block", "version": "0"],
					content: .nodes([
						BinaryNode(tag: "snapshot", content: .data(try blob.serializedData()))
					])
				)
			]))
		]))

		let collection = try #require(try await AppStateSyncExtractor.extract(
			from: result,
			downloadExternalBlob: downloader.download(_:)
		)["critical_block"])
		#expect(collection.snapshot?.version.version == 7)
		#expect(collection.snapshot?.mac == Data([4, 5]))
		#expect(await downloader.directPaths == ["/mms/md-app-state/test"])
	}
}

private actor RecordingAppStateBlobDownloader {
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
