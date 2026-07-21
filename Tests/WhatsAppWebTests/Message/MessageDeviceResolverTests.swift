import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Message device resolver")
struct MessageDeviceResolverTests {
	@Test("queries USync device protocol and returns sendable device JIDs")
	func queriesUSyncDeviceProtocolAndReturnsSendableDeviceJIDs() async throws {
		let query = RecordingDeviceQuery(response: usyncDeviceResponse())
		let resolver = USyncMessageDeviceResolver(
			query: query.query(_:timeout:),
			sidGenerator: { "sid-1" }
		)

		let devices = try await resolver.deviceJIDs(for: "123@s.whatsapp.net")

		#expect(devices == ["123:0@s.whatsapp.net", "123:2@s.whatsapp.net"])
		#expect(
			await query.requests == [
				BinaryNode(
					tag: "iq",
					attrs: ["id": "sid-1", "to": "@s.whatsapp.net", "type": "get", "xmlns": "usync"],
					content: .nodes([
						BinaryNode(
							tag: "usync",
							attrs: ["context": "message", "mode": "query", "sid": "sid-1", "last": "true", "index": "0"],
							content: .nodes([
								BinaryNode(
									tag: "query",
									content: .nodes([
										BinaryNode(tag: "devices", attrs: ["version": "2"]),
										BinaryNode(tag: "lid")
									])
								),
								BinaryNode(
									tag: "list",
									content: .nodes([
										BinaryNode(tag: "user", attrs: ["jid": "123@s.whatsapp.net"])
									])
								)
							])
						)
					])
				)
			]
		)
	}

	@Test("normalizes legacy user JIDs before USync lookup")
	func normalizesLegacyUserJIDsBeforeUSyncLookup() async throws {
		let query = RecordingDeviceQuery(response: usyncDeviceResponse())
		let resolver = USyncMessageDeviceResolver(query: query.query(_:timeout:), sidGenerator: { "sid-2" })

		_ = try await resolver.deviceJIDs(for: "123@c.us")

		let request = await query.requests[0]
		let usync = request.firstChild(named: "usync")
		let list = usync?.firstChild(named: "list")
		#expect(list?.firstChild(named: "user")?.attrs["jid"] == "123@s.whatsapp.net")
	}

	@Test("rejects empty USync request sid")
	func rejectsEmptyUSyncRequestSID() throws {
		#expect(throws: MessageDeviceResolverError.emptySID) {
			try USyncMessageDeviceResolver.makeRequest(for: "123@s.whatsapp.net", sid: "")
		}
	}

	private func usyncDeviceResponse() -> BinaryNode {
		BinaryNode(
			tag: "iq",
			attrs: ["type": "result"],
			content: .nodes([
				BinaryNode(
					tag: "usync",
					content: .nodes([
						BinaryNode(
							tag: "list",
							content: .nodes([
								BinaryNode(
									tag: "user",
									attrs: ["jid": "123@s.whatsapp.net"],
									content: .nodes([
										BinaryNode(
											tag: "devices",
											content: .nodes([
												BinaryNode(
													tag: "device-list",
													content: .nodes([
														BinaryNode(tag: "device", attrs: ["id": "0"]),
														BinaryNode(tag: "device", attrs: ["id": "2", "key-index": "7"]),
														BinaryNode(tag: "device", attrs: ["id": "3"])
													])
												)
											])
										)
									])
								)
							])
						)
					])
				)
			])
		)
	}
}

private actor RecordingDeviceQuery {
	private let response: BinaryNode
	private(set) var requests: [BinaryNode] = []

	init(response: BinaryNode) {
		self.response = response
	}

	func query(_ node: BinaryNode, timeout: Duration) async throws -> BinaryNode {
		#expect(timeout == .seconds(60))
		requests.append(node)
		return response
	}
}
