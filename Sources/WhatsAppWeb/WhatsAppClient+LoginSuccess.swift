import Foundation

extension WhatsAppClient {
	/// Handles the server's `<success>` after a login: goes active, starts keep-alive pings and
	/// announces the connection to the app.
	func handleLoginSuccessNode(_ node: BinaryNode) async -> Bool {
		guard node.tag == "success" else {
			return false
		}

		if let lid = node.attrs["lid"], authenticationState?.credentials.me != nil {
			try? await updateCredentials { credentials in
				credentials.me?.lid = lid
			}
		}

		if let id = try? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id) {
			try? await sendNode(BinaryNode(
				tag: "iq",
				attrs: ["to": "@s.whatsapp.net", "xmlns": "passive", "type": "set", "id": id],
				content: .nodes([BinaryNode(tag: "active")])
			))
		}

		startKeepAlive()
		eventContinuation.yield(.connected(user: authenticationState?.credentials.me?.id ?? ""))
		return true
	}

	private func startKeepAlive() {
		keepAliveTask?.cancel()
		keepAliveTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: .seconds(25))
				guard !Task.isCancelled, let self else { return }
				guard let id = try? await self.messageIDGenerator.generateV2(userID: nil) else { continue }
				_ = try? await self.query(
					BinaryNode(
						tag: "iq",
						attrs: ["to": "@s.whatsapp.net", "type": "get", "xmlns": "w:p", "id": id],
						content: .nodes([BinaryNode(tag: "ping")])
					),
					timeout: .seconds(20)
				)
			}
		}
	}
}
