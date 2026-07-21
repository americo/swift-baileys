import Foundation

public struct MediaConnectionHost: Equatable, Sendable {
	public let hostname: String
	public let maxContentLengthBytes: Int

	public init(hostname: String, maxContentLengthBytes: Int) {
		self.hostname = hostname
		self.maxContentLengthBytes = maxContentLengthBytes
	}
}

public struct MediaConnectionInfo: Equatable, Sendable {
	public let hosts: [MediaConnectionHost]
	public let auth: String
	public let ttl: Int

	public init(hosts: [MediaConnectionHost], auth: String, ttl: Int) {
		self.hosts = hosts
		self.auth = auth
		self.ttl = ttl
	}
}

public struct MediaConnectionResolver: Sendable {
	public typealias Query = @Sendable (_ node: BinaryNode, _ timeout: Duration) async throws -> BinaryNode

	private let query: Query
	private let idGenerator: @Sendable () -> String

	public init(query: @escaping Query, idGenerator: @escaping @Sendable () -> String = { UUID().uuidString }) {
		self.query = query
		self.idGenerator = idGenerator
	}

	public func fetchConnection() async throws -> MediaConnectionInfo {
		let response = try await query(Self.makeRequest(id: idGenerator()), .seconds(60))
		return try Self.parseConnection(from: response)
	}

	public static func makeRequest(id: String) -> BinaryNode {
		BinaryNode(
			tag: "iq",
			attrs: ["id": id, "type": "set", "xmlns": "w:m", "to": "@s.whatsapp.net"],
			content: .nodes([
				BinaryNode(tag: "media_conn")
			])
		)
	}

	public static func parseConnection(from response: BinaryNode) throws -> MediaConnectionInfo {
		guard response.attrs["type"] == "result",
			  let mediaConnection = response.firstChild(named: "media_conn"),
			  let auth = mediaConnection.attrs["auth"],
			  let ttlValue = mediaConnection.attrs["ttl"],
			  let ttl = Int(ttlValue),
			  !auth.isEmpty,
			  ttl > 0 else {
			throw MediaConnectionResolverError.invalidResponse
		}

		let hosts = try mediaConnection.children(named: "host").map { hostNode in
			guard let hostname = hostNode.attrs["hostname"],
				  let maxContentLengthValue = hostNode.attrs["maxContentLengthBytes"],
				  let maxContentLengthBytes = Int(maxContentLengthValue),
				  !hostname.isEmpty,
				  maxContentLengthBytes > 0 else {
				throw MediaConnectionResolverError.invalidResponse
			}

			return MediaConnectionHost(hostname: hostname, maxContentLengthBytes: maxContentLengthBytes)
		}

		guard !hosts.isEmpty else {
			throw MediaConnectionResolverError.invalidResponse
		}

		return MediaConnectionInfo(hosts: hosts, auth: auth, ttl: ttl)
	}
}

public enum MediaConnectionResolverError: Error, Equatable, Sendable {
	case invalidResponse
}
