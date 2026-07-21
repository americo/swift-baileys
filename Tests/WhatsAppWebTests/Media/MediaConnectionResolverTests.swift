import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Media connection resolver")
struct MediaConnectionResolverTests {
	@Test("queries media connection and parses hosts")
	func queriesMediaConnectionAndParsesHosts() async throws {
		let query = RecordingMediaConnectionQuery(response: mediaConnectionResponse())
		let resolver = MediaConnectionResolver(query: query.query(_:timeout:), idGenerator: { "media-1" })

		let connection = try await resolver.fetchConnection()

		#expect(
			await query.requests == [
				BinaryNode(
					tag: "iq",
					attrs: ["id": "media-1", "type": "set", "xmlns": "w:m", "to": "@s.whatsapp.net"],
					content: .nodes([
						BinaryNode(tag: "media_conn")
					])
				)
			]
		)
		#expect(connection == MediaConnectionInfo(
			hosts: [
				MediaConnectionHost(hostname: "mmg.whatsapp.net", maxContentLengthBytes: 1_048_576),
				MediaConnectionHost(hostname: "mmg-alt.whatsapp.net", maxContentLengthBytes: 2_097_152)
			],
			auth: "auth-token",
			ttl: 1_200
		))
	}

	@Test("rejects malformed media connection responses")
	func rejectsMalformedMediaConnectionResponses() throws {
		for response in [
			mediaConnectionResponse(auth: ""),
			mediaConnectionResponse(ttl: "0"),
			mediaConnectionResponse(hosts: []),
			mediaConnectionResponse(hosts: [
				BinaryNode(tag: "host", attrs: ["hostname": "", "maxContentLengthBytes": "1048576"])
			]),
			mediaConnectionResponse(hosts: [
				BinaryNode(tag: "host", attrs: ["hostname": "mmg.whatsapp.net", "maxContentLengthBytes": "0"])
			])
		] {
			#expect(throws: MediaConnectionResolverError.invalidResponse) {
				try MediaConnectionResolver.parseConnection(from: response)
			}
		}
	}

	private func mediaConnectionResponse(
		auth: String = "auth-token",
		ttl: String = "1200",
		hosts: [BinaryNode] = [
			BinaryNode(tag: "host", attrs: ["hostname": "mmg.whatsapp.net", "maxContentLengthBytes": "1048576"]),
			BinaryNode(tag: "host", attrs: ["hostname": "mmg-alt.whatsapp.net", "maxContentLengthBytes": "2097152"])
		]
	) -> BinaryNode {
		BinaryNode(
			tag: "iq",
			attrs: ["type": "result"],
			content: .nodes([
				BinaryNode(
					tag: "media_conn",
					attrs: ["auth": auth, "ttl": ttl],
					content: .nodes(hosts)
				)
			])
		)
	}
}

private actor RecordingMediaConnectionQuery {
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
