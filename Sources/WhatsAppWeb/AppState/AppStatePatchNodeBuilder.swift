import Foundation

enum AppStatePatchNodeBuilder {
	static func syncIQ(
		for patchType: ChatModificationPatchType,
		encodingResult: AppStatePatchEncodingResult,
		requestID: String
	) throws -> BinaryNode {
		guard !requestID.isEmpty else {
			throw AppStatePatchNodeBuilderError.emptyRequestID
		}

		return BinaryNode(
			tag: "iq",
			attrs: ["id": requestID, "to": "@s.whatsapp.net", "type": "set", "xmlns": "w:sync:app:state"],
			content: .nodes([
				BinaryNode(
					tag: "sync",
					content: .nodes([
						BinaryNode(
							tag: "collection",
							attrs: [
								"name": patchType.rawValue,
								"version": String(encodingResult.state.version - 1),
								"return_snapshot": "false"
							],
							content: .nodes([
								BinaryNode(
									tag: "patch",
									content: .data(try encodingResult.patch.serializedData())
								)
							])
						)
					])
				)
			])
		)
	}
}

enum AppStatePatchNodeBuilderError: Error, Equatable, Sendable {
	case emptyRequestID
}
