import Foundation

extension WhatsAppClient {
	/// After login the server announces the messages queued while this device was offline
	/// (`<ib><offline_preview/></ib>`) and only delivers them once the client asks for a batch.
	func handleOfflineNode(_ node: BinaryNode) async -> Bool {
		guard node.tag == "ib" else {
			return false
		}

		if let preview = node.firstChild(named: "offline_preview") {
			WhatsAppLog.logger.notice("offline preview \(String(describing: preview.attrs), privacy: .public); requesting batch")
			try? await sendNode(BinaryNode(
				tag: "ib",
				content: .nodes([BinaryNode(tag: "offline_batch", attrs: ["count": "100"])])
			))
			return true
		}

		if let offline = node.firstChild(named: "offline") {
			WhatsAppLog.logger.notice("offline messages delivered \(String(describing: offline.attrs), privacy: .public)")
			return true
		}

		return false
	}
}
