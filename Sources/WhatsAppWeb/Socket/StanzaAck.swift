import Foundation

enum StanzaAck {
	static func build(for node: BinaryNode, errorCode: Int? = nil, meID: String? = nil) -> BinaryNode? {
		guard let id = node.attrs["id"], let from = node.attrs["from"] else {
			return nil
		}

		let attrs = BinaryNodeAttributes.trimmingUndefined([
			("id", id),
			("to", from),
			("class", node.tag),
			("error", errorCode.flatMap { $0 == 0 ? nil : String($0) }),
			("participant", node.attrs["participant"]),
			("recipient", node.attrs["recipient"]),
			("type", node.attrs["type"]),
			("from", node.tag == "message" ? meID : nil)
		])
		return BinaryNode(tag: "ack", attrs: attrs)
	}
}
