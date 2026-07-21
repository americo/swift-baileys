import Foundation

public protocol MessageDeviceResolving: Sendable {
	func deviceJIDs(for jid: String) async throws -> [String]
	func deviceJIDs(for jid: String, useCache: Bool) async throws -> [String]
}

public extension MessageDeviceResolving {
	func deviceJIDs(for jid: String, useCache: Bool) async throws -> [String] {
		try await deviceJIDs(for: jid)
	}
}

public struct USyncMessageDeviceResolver: MessageDeviceResolving {
	public typealias Query = @Sendable (_ node: BinaryNode, _ timeout: Duration) async throws -> BinaryNode

	private let query: Query
	private let sidGenerator: @Sendable () -> String

	public init(
		query: @escaping Query,
		sidGenerator: @escaping @Sendable () -> String = {
			UUID().uuidString
		}
	) {
		self.query = query
		self.sidGenerator = sidGenerator
	}

	public func deviceJIDs(for jid: String) async throws -> [String] {
		try await deviceJIDs(for: jid, useCache: true)
	}

	public func deviceJIDs(for jid: String, useCache: Bool) async throws -> [String] {
		let request = try Self.makeRequest(for: jid, sid: sidGenerator())
		let response = try await query(request, .seconds(60))
		return try Self.parseDeviceJIDs(from: response, matching: jid)
	}

	public static func makeRequest(for jid: String, sid: String) throws -> BinaryNode {
		guard !sid.isEmpty else {
			throw MessageDeviceResolverError.emptySID
		}

		guard let parsedJID = JID(jid) else {
			throw MessageDeviceResolverError.invalidJID
		}

		let lookupJID = parsedJID.normalizedUser
		return BinaryNode(
			tag: "iq",
			attrs: ["id": sid, "to": "@s.whatsapp.net", "type": "get", "xmlns": "usync"],
			content: .nodes([
				BinaryNode(
					tag: "usync",
					attrs: ["context": "message", "mode": "query", "sid": sid, "last": "true", "index": "0"],
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
								BinaryNode(tag: "user", attrs: ["jid": lookupJID])
							])
						)
					])
				)
			])
		)
	}

	public static func parseDeviceJIDs(from response: BinaryNode, matching jid: String) throws -> [String] {
		guard let parsedJID = JID(jid) else {
			throw MessageDeviceResolverError.invalidJID
		}

		let lookupJID = parsedJID.normalizedUser
		guard response.attrs["type"] == "result" else {
			throw MessageDeviceResolverError.invalidUSyncResponse
		}

		var devices: [String] = []
		let users = response.firstChild(named: "usync")?.firstChild(named: "list")?.children(named: "user") ?? []
		for user in users where user.attrs["jid"] == lookupJID {
			guard let userJID = JID(user.attrs["jid"]) else {
				continue
			}

			for device in user.firstChild(named: "devices")?.firstChild(named: "device-list")?.children(named: "device") ?? [] {
				guard let idValue = device.attrs["id"], let id = Int(idValue) else {
					continue
				}

				if id != 0 && device.attrs["key-index"] == nil {
					continue
				}

				let server: String
				if device.attrs["is_hosted"] == "true" {
					server = userJID.server == JIDServer.lid.rawValue ? JIDServer.hostedLid.rawValue : JIDServer.hosted.rawValue
				} else {
					server = userJID.server
				}

				devices.append(JID.encode(user: userJID.user, server: server, device: id))
			}
		}

		return devices
	}
}

public enum MessageDeviceResolverError: Error, Equatable, Sendable {
	case emptySID
	case invalidJID
	case invalidUSyncResponse
}
