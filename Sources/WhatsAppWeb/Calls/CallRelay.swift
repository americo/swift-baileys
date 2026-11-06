import Foundation

public struct CallRelayAddress: Equatable, Sendable {
	public let protocolID: UInt8
	public let ipv4: String?
	public let ipv6: String?
	public let port: UInt16
}

public struct CallRelayEndpoint: Equatable, Sendable {
	public let relayID: UInt32
	public let relayName: String
	public let tokenID: Int
	public let authTokenID: Int
	public let isFNA: Bool
	/// Raw 6-byte IPv4:port of the first IPv4 `<te2>`; echoed verbatim in `<relaylatency>`.
	public let ipv4Bytes: Data?
	public let addresses: [CallRelayAddress]
	public let clientToRelayRTTMs: Int?

	/// First IPv4 address and port of this relay.
	public var primaryIPv4: (host: String, port: UInt16)? {
		addresses.lazy.compactMap { address in address.ipv4.map { ($0, address.port) } }.first
	}
}

/// The `<relay>` block of a call ack or offer: keys, tokens and the relay endpoints to dial.
public struct CallRelayData: Equatable, Sendable {
	public static let hopByHopKeyLength = 30
	/// Upper bound on a token index. The relay is untrusted, so an unbounded id must not force a
	/// huge allocation.
	static let maxTokens = 64

	/// 14-byte salt seed followed by a 16-byte key seed.
	public var hopByHopKey: Data?
	/// Raw `<hbh_key>` content (ASCII base64).
	public var hopByHopKeyASCII: Data?
	public var relayKey: Data?
	/// Raw `<key>` content before decoding: the STUN MESSAGE-INTEGRITY key material.
	public var relayKeyASCII: Data?
	public var warpTagLength: Int?
	public var uuid: String?
	public var selfPID: UInt32?
	public var peerPID: UInt32?
	public var relayTokens: [Data]
	public var authTokens: [Data]
	public var endpoints: [CallRelayEndpoint]

	/// Port the WhatsApp Web client dials; preferred when an endpoint offers it.
	public static let webClientPort: UInt16 = 3480

	/// The relay to carry media: prefers one on the web client port, then an outbound candidate
	/// (not FNA, with an auth token), then any non-FNA one, then the first. At each tier an endpoint
	/// that has both an IPv4 address to dial and a token we hold wins over one that does not.
	public func mediaEndpoint() -> CallRelayEndpoint? {
		func isUsable(_ endpoint: CallRelayEndpoint) -> Bool {
			endpoint.primaryIPv4 != nil && relayTokens.indices.contains(endpoint.tokenID)
				&& !relayTokens[endpoint.tokenID].isEmpty
		}

		func pick(usableOnly: Bool) -> CallRelayEndpoint? {
			let candidates = endpoints.filter { !usableOnly || isUsable($0) }
			return candidates.first { $0.primaryIPv4?.port == Self.webClientPort }
				?? candidates.first { !$0.isFNA && $0.authTokenID != 0 }
				?? candidates.first { !$0.isFNA }
				?? candidates.first
		}

		return pick(usableOnly: true) ?? pick(usableOnly: false)
	}

	/// Finds and parses the `<relay>` child of a call ack or offer node.
	public static func parse(fromAck node: BinaryNode) -> CallRelayData? {
		findRelay(in: node).flatMap(parse(relay:))
	}

	/// The first `<relay>` at any depth: its position differs between acks and offers.
	static func findRelay(in node: BinaryNode) -> BinaryNode? {
		if node.tag == "relay" {
			return node
		}
		guard case let .nodes(children)? = node.content else {
			return nil
		}

		return children.lazy.compactMap(findRelay(in:)).first
	}

	public static func parse(relay: BinaryNode) -> CallRelayData? {
		guard case let .nodes(children)? = relay.content else {
			return nil
		}

		func firstBytes(_ tag: String) -> Data? {
			children.first { $0.tag == tag }.flatMap(contentBytes)
		}

		let keyBytes = firstBytes("key")
		let hbhBytes = firstBytes("hbh_key")
		let tagLength = firstBytes("warp_mi_tag_len")
			.flatMap { String(data: $0, encoding: .utf8) }
			.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
			.flatMap { $0 > 0 ? $0 : nil }

		return CallRelayData(
			hopByHopKey: hbhBytes.flatMap(decodeHopByHopKey),
			hopByHopKeyASCII: hbhBytes,
			relayKey: keyBytes.map(decodeRelayKey),
			relayKeyASCII: keyBytes,
			warpTagLength: tagLength,
			uuid: relay.attrs["uuid"],
			selfPID: relay.attrs["self_pid"].flatMap(UInt32.init),
			peerPID: relay.attrs["peer_pid"].flatMap(UInt32.init),
			relayTokens: indexedTokens(children, tag: "token"),
			authTokens: indexedTokens(children, tag: "auth_token"),
			endpoints: parseEndpoints(children)
		)
	}

	/// The `<hbh_key>` is base64 (sometimes twice) of a 30-byte seed.
	static func decodeHopByHopKey(_ bytes: Data) -> Data? {
		guard !bytes.isEmpty else {
			return nil
		}

		var decoded = base64Decoded(bytes) ?? bytes
		if decoded.count != hopByHopKeyLength, let inner = base64Decoded(decoded), inner.count == hopByHopKeyLength {
			decoded = inner
		}

		return decoded.count == hopByHopKeyLength ? decoded : nil
	}

	static func decodeRelayKey(_ bytes: Data) -> Data {
		base64Decoded(bytes) ?? bytes
	}

	static func base64Decoded(_ bytes: Data) -> Data? {
		guard bytes.count >= 4,
			  bytes.allSatisfy({ isBase64Character($0) }),
			  let text = String(data: bytes, encoding: .ascii) else {
			return nil
		}

		if let decoded = Data(base64Encoded: text) {
			return decoded
		}

		let stripped = text.trimmingCharacters(in: CharacterSet(charactersIn: "="))
		let padded = stripped + String(repeating: "=", count: (4 - stripped.count % 4) % 4)
		return Data(base64Encoded: padded)
	}

	private static func isBase64Character(_ byte: UInt8) -> Bool {
		switch byte {
		case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
			 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "+"), UInt8(ascii: "/"), UInt8(ascii: "="):
			true
		default:
			false
		}
	}

	static func contentBytes(_ node: BinaryNode) -> Data? {
		switch node.content {
		case let .data(data):
			data
		case let .string(text):
			Data(text.utf8)
		default:
			nil
		}
	}

	private static func indexedTokens(_ children: [BinaryNode], tag: String) -> [Data] {
		var tokens = [Data]()
		for node in children where node.tag == tag {
			guard let bytes = contentBytes(node) else {
				continue
			}

			let index = node.attrs["id"].flatMap { Int($0) } ?? tokens.count
			guard index >= 0, index < maxTokens else {
				continue
			}

			while tokens.count <= index {
				tokens.append(Data())
			}
			tokens[index] = bytes
		}

		return tokens
	}

	private static func parseEndpoints(_ children: [BinaryNode]) -> [CallRelayEndpoint] {
		struct Builder {
			var relayID: UInt32
			var relayName: String
			var tokenID: Int
			var authTokenID: Int
			var isFNA: Bool
			var ipv4Bytes: Data?
			var addresses: [CallRelayAddress] = []
			var rtt: Int?
		}

		var builders = [Builder]()
		var indexByKey = [String: Int]()
		for te2 in children where te2.tag == "te2" {
			guard let bytes = contentBytes(te2) else {
				continue
			}

			let protocolID = te2.attrs["protocol"].flatMap(UInt8.init) ?? 0
			guard let address = parseAddress(bytes, protocolID: protocolID) else {
				continue
			}

			let relayID = te2.attrs["relay_id"].flatMap(UInt32.init) ?? 0
			let relayName = te2.attrs["relay_name"] ?? ""
			let rtt = te2.attrs["c2r_rtt"].flatMap { Int($0) }
			let key = "\(relayID):\(relayName)"
			let index = indexByKey[key] ?? {
				builders.append(Builder(
					relayID: relayID,
					relayName: relayName,
					tokenID: te2.attrs["token_id"].flatMap { Int($0) } ?? 0,
					authTokenID: te2.attrs["auth_token_id"].flatMap { Int($0) } ?? 0,
					isFNA: te2.attrs["is_fna"] == "1"
				))
				indexByKey[key] = builders.count - 1
				return builders.count - 1
			}()

			builders[index].addresses.append(address)
			if let rtt {
				builders[index].rtt = rtt
			}
			if bytes.count == 6, builders[index].ipv4Bytes == nil {
				builders[index].ipv4Bytes = bytes
			}
		}

		return builders.map {
			CallRelayEndpoint(
				relayID: $0.relayID,
				relayName: $0.relayName,
				tokenID: $0.tokenID,
				authTokenID: $0.authTokenID,
				isFNA: $0.isFNA,
				ipv4Bytes: $0.ipv4Bytes,
				addresses: $0.addresses,
				clientToRelayRTTMs: $0.rtt
			)
		}
	}

	/// `<te2>` content is either 6 bytes (IPv4 + port) or 18 bytes (IPv6 + port).
	static func parseAddress(_ bytes: Data, protocolID: UInt8) -> CallRelayAddress? {
		let b = Array(bytes)
		switch b.count {
		case 6:
			return CallRelayAddress(
				protocolID: protocolID,
				ipv4: "\(b[0]).\(b[1]).\(b[2]).\(b[3])",
				ipv6: nil,
				port: UInt16(b[4]) << 8 | UInt16(b[5])
			)
		case 18:
			let groups = stride(from: 0, to: 16, by: 2).map { index in
				String(UInt16(b[index]) << 8 | UInt16(b[index + 1]), radix: 16)
			}
			return CallRelayAddress(
				protocolID: protocolID,
				ipv4: nil,
				ipv6: groups.joined(separator: ":"),
				port: UInt16(b[16]) << 8 | UInt16(b[17])
			)
		default:
			return nil
		}
	}
}
