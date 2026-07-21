import Foundation

struct AppStateSyncCollectionRequest: Equatable, Sendable {
	let name: AppStateCollectionName
	let version: UInt64
	let returnSnapshot: Bool
}

enum AppStateSyncRequestNodeBuilder {
	static func syncIQ(collections: [AppStateSyncCollectionRequest], requestID: String) throws -> BinaryNode {
		guard !requestID.isEmpty else {
			throw AppStateSyncRequestNodeBuilderError.emptyRequestID
		}
		guard !collections.isEmpty else {
			throw AppStateSyncRequestNodeBuilderError.emptyCollections
		}

		return BinaryNode(
			tag: "iq",
			attrs: ["id": requestID, "to": "@s.whatsapp.net", "type": "set", "xmlns": "w:sync:app:state"],
			content: .nodes([
				BinaryNode(
					tag: "sync",
					content: .nodes(collections.map { collection in
						BinaryNode(
							tag: "collection",
							attrs: [
								"name": collection.name.rawValue,
								"version": String(collection.version),
								"return_snapshot": String(collection.returnSnapshot)
							]
						)
					})
				)
			])
		)
	}
}

enum AppStateSyncRequestNodeBuilderError: Error, Equatable, Sendable {
	case emptyRequestID
	case emptyCollections
}
