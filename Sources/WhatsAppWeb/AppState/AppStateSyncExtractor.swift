import Foundation

typealias AppStateExternalBlobDownloader = @Sendable (Proto_ExternalBlobReference) async throws -> Data

struct AppStateSyncCollection: Equatable, Sendable {
	let name: String
	let patches: [Proto_SyncdPatch]
	let hasMorePatches: Bool
	let snapshot: Proto_SyncdSnapshot?
}

enum AppStateSyncExtractionError: Error, Equatable {
	case missingSyncNode
	case missingCollectionName
	case missingPatchData
	case missingSnapshotData
	case missingSnapshotDownloader
	case invalidCollectionVersion(String)
}

enum AppStateSyncExtractor {
	static func extract(
		from result: BinaryNode,
		downloadExternalBlob: AppStateExternalBlobDownloader? = nil
	) async throws -> [String: AppStateSyncCollection] {
		guard let sync = result.firstChild(named: "sync") else {
			throw AppStateSyncExtractionError.missingSyncNode
		}

		var collections: [String: AppStateSyncCollection] = [:]
		for collection in sync.children(named: "collection") {
			guard let name = collection.attrs["name"] else {
				throw AppStateSyncExtractionError.missingCollectionName
			}

			let patchesRoot = collection.firstChild(named: "patches") ?? collection
			let patches = try patchesRoot.children(named: "patch").map { patchNode in
				guard let data = patchNode.dataContent else {
					throw AppStateSyncExtractionError.missingPatchData
				}

				var patch = try Proto_SyncdPatch(serializedBytes: data)
				if !patch.hasVersion {
					guard let rawVersion = collection.attrs["version"], let version = UInt64(rawVersion) else {
						throw AppStateSyncExtractionError.invalidCollectionVersion(collection.attrs["version"] ?? "")
					}

					patch.version.version = version + 1
				}
				return patch
			}

			let snapshot = try await decodeSnapshot(from: collection, downloadExternalBlob: downloadExternalBlob)
			collections[name] = AppStateSyncCollection(
				name: name,
				patches: patches,
				hasMorePatches: collection.attrs["has_more_patches"] == "true",
				snapshot: snapshot
			)
		}

		return collections
	}

	private static func decodeSnapshot(
		from collection: BinaryNode,
		downloadExternalBlob: AppStateExternalBlobDownloader?
	) async throws -> Proto_SyncdSnapshot? {
		guard let snapshotNode = collection.firstChild(named: "snapshot") else {
			return nil
		}
		guard let data = snapshotNode.dataContent else {
			throw AppStateSyncExtractionError.missingSnapshotData
		}
		guard let downloadExternalBlob else {
			throw AppStateSyncExtractionError.missingSnapshotDownloader
		}

		let blobReference = try Proto_ExternalBlobReference(serializedBytes: data)
		return try Proto_SyncdSnapshot(serializedBytes: await downloadExternalBlob(blobReference))
	}
}

private extension BinaryNode {
	var dataContent: Data? {
		guard case let .data(data) = content else {
			return nil
		}

		return data
	}
}
