import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client WMex queries")
struct WhatsAppClientWMexQueryTests {
	@Test("sends Baileys-compatible WMex query and returns selected data")
	func sendsBaileysCompatibleWMexQueryAndReturnsSelectedData() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			let response = try await client.executeWMexQuery(
				variables: ["newsletter_id": "120363000000000010@newsletter"],
				queryID: "9783111038412085",
				dataPath: "xwa2_newsletter_subscribers",
				requestID: "wmex-1"
			)
			return response["subscribers"] as? Int
		}

		let request = try await sentNode(from: transport)
		#expect(request.attrs["id"] == "wmex-1")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["xmlns"] == "w:mex")
		let query = try #require(request.firstChild(named: "query"))
		#expect(query.attrs["query_id"] == "9783111038412085")

		await transport.enqueueInbound(wmexResponse(
			id: "wmex-1",
			json: ["data": ["xwa2_newsletter_subscribers": ["subscribers": 42]]]
		))
		#expect(try await task.value == 42)
	}

	@Test("throws typed server errors from WMex responses")
	func throwsTypedServerErrorsFromWMexResponses() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			_ = try await client.executeWMexQuery(
				variables: [:],
				queryID: "query-id",
				dataPath: "xwa2_action",
				requestID: "wmex-error"
			)
		}
		_ = try await sentNode(from: transport)
		await transport.enqueueInbound(wmexResponse(
			id: "wmex-error",
			json: [
				"errors": [
					[
						"message": "Forbidden",
						"extensions": ["error_code": 403]
					]
				]
			]
		))
		await #expect(throws: WMexQueryError.serverError(message: "Forbidden", code: 403)) {
			try await task.value
		}
	}

	@Test("throws when WMex result node is missing")
	func throwsWhenWMexResultNodeIsMissing() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			_ = try await client.executeWMexQuery(
				variables: [:],
				queryID: "query-id",
				dataPath: "xwa2_action",
				requestID: "wmex-missing"
			)
		}
		_ = try await sentNode(from: transport)
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "wmex-missing", "type": "result"]))
		await #expect(throws: WMexQueryError.missingResult) {
			try await task.value
		}
	}
}

private func wmexResponse(id: String, json: [String: Any]) -> BinaryNode {
	let data = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
	return BinaryNode(
		tag: "iq",
		attrs: ["id": id, "type": "result"],
		content: .nodes([BinaryNode(tag: "result", content: .data(data))])
	)
}

private func sentNode(from transport: MockMessageSendWebSocketTransport) async throws -> BinaryNode {
	let frame = try await transport.waitForSentFrame()
	var codec = NoiseFrameCodec()
	return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
}
