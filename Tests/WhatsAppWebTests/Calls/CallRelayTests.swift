import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Call relay data")
struct CallRelayTests {
	private func relayNode() -> BinaryNode {
		let hbh = Data((0..<30).map(UInt8.init)).base64EncodedString()
		return BinaryNode(
			tag: "relay",
			attrs: ["uuid": "abc", "self_pid": "1", "peer_pid": "2"],
			content: .nodes([
				BinaryNode(tag: "key", content: .data(Data("c2VjcmV0LWtleS0xMjM0NQ==".utf8))),
				BinaryNode(tag: "hbh_key", content: .data(Data(hbh.utf8))),
				BinaryNode(tag: "warp_mi_tag_len", content: .data(Data("4".utf8))),
				BinaryNode(tag: "token", attrs: ["id": "1"], content: .data(Data([0xb]))),
				BinaryNode(tag: "token", attrs: ["id": "0"], content: .data(Data([0xa]))),
				BinaryNode(tag: "auth_token", attrs: ["id": "0"], content: .data(Data([0xc]))),
				BinaryNode(
					tag: "te2",
					attrs: ["relay_id": "7", "relay_name": "gru1", "token_id": "1", "auth_token_id": "0", "protocol": "0", "c2r_rtt": "12"],
					content: .data(Data([157, 240, 226, 133, 0x0d, 0x96]))
				),
				BinaryNode(
					tag: "te2",
					attrs: ["relay_id": "7", "relay_name": "gru1", "protocol": "1"],
					content: .data(Data([157, 240, 226, 133, 0x01, 0xbb]))
				),
				BinaryNode(
					tag: "te2",
					attrs: ["relay_id": "8", "relay_name": "gig1", "is_fna": "1"],
					content: .data(Data([0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x0d, 0x96]))
				),
				BinaryNode(tag: "te2", attrs: ["relay_id": "9"], content: .data(Data([1, 2, 3])))
			])
		)
	}

	@Test("parses keys, ids and tokens")
	func parsesKeysIdsAndTokens() throws {
		let relay = try #require(CallRelayData.parse(relay: relayNode()))

		#expect(relay.uuid == "abc")
		#expect(relay.selfPID == 1)
		#expect(relay.peerPID == 2)
		#expect(relay.warpTagLength == 4)
		#expect(relay.hopByHopKey == Data((0..<30).map(UInt8.init)))
		#expect(relay.relayKey == Data("secret-key-12345".utf8))
		#expect(relay.relayKeyASCII == Data("c2VjcmV0LWtleS0xMjM0NQ==".utf8))
		#expect(relay.relayTokens == [Data([0xa]), Data([0xb])])
		#expect(relay.authTokens == [Data([0xc])])
	}

	@Test("groups te2 addresses per relay and skips malformed ones")
	func groupsAddressesPerRelay() throws {
		let relay = try #require(CallRelayData.parse(relay: relayNode()))

		#expect(relay.endpoints.map(\.relayName) == ["gru1", "gig1"])
		let gru = relay.endpoints[0]
		#expect(gru.addresses.map(\.port) == [3478, 443])
		#expect(gru.addresses.first?.ipv4 == "157.240.226.133")
		#expect(gru.ipv4Bytes == Data([157, 240, 226, 133, 0x0d, 0x96]))
		#expect(gru.clientToRelayRTTMs == 12)
		#expect(gru.tokenID == 1)

		let gig = relay.endpoints[1]
		#expect(gig.isFNA)
		#expect(gig.addresses.first?.ipv6 == "2001:db8:0:0:0:0:0:1")
		#expect(gig.ipv4Bytes == nil)
	}

	@Test("finds the relay inside an ack")
	func findsRelayInsideAck() {
		let ack = BinaryNode(tag: "ack", attrs: ["class": "call"], content: .nodes([relayNode()]))

		#expect(CallRelayData.parse(fromAck: ack)?.uuid == "abc")
		#expect(CallRelayData.parse(fromAck: BinaryNode(tag: "ack")) == nil)
	}

	@Test("decodes a doubly base64 hop-by-hop key")
	func decodesDoublyEncodedHopByHopKey() {
		let seed = Data((0..<30).map(UInt8.init))
		let twice = Data(seed.base64EncodedString().data(using: .ascii)!.base64EncodedString().utf8)

		#expect(CallRelayData.decodeHopByHopKey(twice) == seed)
		#expect(CallRelayData.decodeHopByHopKey(Data()) == nil)
		#expect(CallRelayData.decodeHopByHopKey(Data("short".utf8)) == nil)
	}

	@Test("ignores token ids beyond the bound")
	func ignoresOutOfBoundTokenIDs() throws {
		let node = BinaryNode(tag: "relay", content: .nodes([
			BinaryNode(tag: "token", attrs: ["id": "9999"], content: .data(Data([1]))),
			BinaryNode(tag: "token", attrs: ["id": "0"], content: .data(Data([2])))
		]))
		let relay = try #require(CallRelayData.parse(relay: node))

		#expect(relay.relayTokens == [Data([2])])
	}
}
