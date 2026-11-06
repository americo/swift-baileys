import Foundation
import Testing
@testable import WhatsAppWeb

private func hex(_ data: Data) -> String {
	data.map { String(format: "%02x", $0) }.joined()
}

private func participant(_ user: String, device: Int = 1, pid: UInt32?, state: String = "connected") -> GroupCallParticipant {
	GroupCallParticipant(
		jid: "\(user)@lid",
		state: state,
		devices: [GroupCallDevice(jid: "\(user):\(device)@lid", pid: pid)]
	)
}

private func update(
	_ transaction: UInt32,
	_ participants: [GroupCallParticipant],
	media: String = "video",
	limit: UInt32 = 32,
	rekey: Bool = false,
	relay: CallRelayData? = nil,
	group: String? = nil
) -> GroupCallUpdate {
	GroupCallUpdate(
		callID: "CALL",
		callCreator: "100001:1@lid",
		groupJID: group,
		transactionID: transaction,
		media: media,
		connectedLimit: limit,
		isRekeyRequested: rekey,
		participants: participants,
		relay: relay
	)
}

private func relay(transaction: UInt32?, host: [UInt8] = [10, 0, 0, 1]) -> CallRelayData {
	CallRelayData.parse(relay: BinaryNode(
		tag: "relay",
		attrs: BinaryNodeAttributes.trimmingUndefined([
			("transaction-id", transaction.map(String.init)),
			("uuid", "RELAY"),
			("participant_uuid", "PARTICIPANT"),
			("self_pid", "1"),
			("warp_mi_tag_len", "4")
		]),
		content: .nodes([
			BinaryNode(tag: "key", content: .data(Data("integrity-key".utf8))),
			BinaryNode(tag: "hbh_key", content: .data(Data("abc".utf8))),
			BinaryNode(tag: "token", attrs: ["id": "0"], content: .data(Data("token".utf8))),
			BinaryNode(tag: "auth_token", attrs: ["id": "0"], content: .data(Data("auth".utf8))),
			BinaryNode(
				tag: "te2",
				attrs: ["relay_id": "1", "token_id": "0", "auth_token_id": "0", "relay_name": "gru"],
				content: .data(Data(host + [0x0d, 0x98]))
			)
		])
	))!
}

@Suite("Group call stanzas")
struct GroupCallStanzaTests {
	@Test("an initial offer goes to the call scope in the order the server enforces")
	func offerShape() throws {
		let node = CallStanzaBuilder.groupOffer(
			callID: "CALL",
			callCreator: "100001:1@lid",
			stanzaID: "REQ",
			groupJID: "1234-5678@g.us",
			participants: [
				GroupCallParticipant(jid: "100001@lid", devices: [GroupCallDevice(
					jid: "100001:1@lid",
					capabilityVersion: 1,
					capability: CallCapability.standardOpusVideoOffer
				)]),
				GroupCallParticipant(jid: "200002@lid", devices: [GroupCallDevice(jid: "200002:2@lid")])
			],
			video: true
		)

		#expect(node.attrs["to"] == "CALL@call")
		let offer = try #require(node.firstChild(named: "offer"))
		#expect(offer.attrs["group-jid"] == "1234-5678@g.us")
		guard case let .nodes(children)? = offer.content else {
			Issue.record("the offer has no children")
			return
		}
		#expect(children.map(\.tag) == ["audio", "video", "net", "group_info"])
		#expect(children[1].attrs["screen_width"] == "1920")

		let users = try #require(offer.firstChild(named: "group_info")).children(named: "user")
		#expect(users.map { $0.attrs["jid"] } == ["100001@lid", "200002@lid"])
		#expect(users[0].attrs["state"] == nil)
		let capability = users[0].firstChild(named: "device")?.firstChild(named: "capability")
		#expect(capability?.attrs["ver"] == "1")
		#expect(users[1].firstChild(named: "device")?.firstChild(named: "capability") == nil)
	}

	@Test("the call scope survives the wire")
	func callScopeRoundTrip() throws {
		let node = CallStanzaBuilder.terminate(
			callID: "00AABB",
			to: groupCallScope(callID: "00AABB"),
			callCreator: "100001:1@lid",
			stanzaID: "REQ"
		)
		let decoded = try BinaryNodeDecoder().decode(BinaryNodeEncoder().encode(node))
		#expect(decoded.attrs["to"] == "00AABB@call")
	}

	@Test("a key goes to one device, under the transaction it belongs to")
	func encRekeyShape() throws {
		let node = CallStanzaBuilder.groupEncRekey(
			callID: "CALL",
			callCreator: "100001:1@lid",
			stanzaID: "REQ",
			transactionID: 7,
			deviceKey: CallOfferDeviceKey(deviceJID: "200002:2@lid", ciphertext: Data([1, 2]), encryptionType: "pkmsg"),
			deviceIdentity: Data([9])
		)

		#expect(node.attrs["to"] == "200002:2@lid")
		let action = try #require(node.firstChild(named: "enc_rekey"))
		#expect(action.attrs["transaction-id"] == "7")
		#expect(action.firstChild(named: "encopt")?.attrs["keygen"] == "2")
		#expect(action.firstChild(named: "enc")?.attrs["type"] == "pkmsg")
		#expect(action.firstChild(named: "device-identity") != nil)
	}

	@Test("a group update parses its roster, relay and flags")
	func parsesUpdate() throws {
		let node = BinaryNode(
			tag: "group_update",
			attrs: ["call-id": "CALL", "call-creator": "100001:1@lid"],
			content: .nodes([
				BinaryNode(
					tag: "group_info",
					attrs: ["transaction-id": "7", "connected-limit": "32", "media": "video", "joinable": "1", "rekey": "1"],
					content: .nodes([BinaryNode(
						tag: "user",
						attrs: ["jid": "200002@lid", "state": "connected", "user_pn": "15550002@s.whatsapp.net"],
						content: .nodes([BinaryNode(tag: "device", attrs: ["jid": "200002:2@lid", "pid": "0"])])
					)])
				),
				BinaryNode(tag: "av_upgrade", attrs: ["av-upgradable": "1"]),
				BinaryNode(
					tag: "relay",
					attrs: ["transaction-id": "1", "uuid": "U", "participant_uuid": "P", "warp_mi_tag_len": "16"],
					content: .nodes([
						BinaryNode(tag: "key", content: .data(Data("k".utf8))),
						BinaryNode(tag: "token", attrs: ["id": "0"], content: .data(Data("t".utf8))),
						BinaryNode(
							tag: "te2",
							attrs: ["relay_id": "1", "token_id": "0", "auth_token_id": "0", "relay_name": "gru"],
							content: .data(Data([10, 0, 0, 1, 0x0d, 0x98]))
						)
					])
				)
			])
		)

		let parsed = try GroupCallUpdate.parse(groupUpdate: node)
		#expect(parsed.transactionID == 7)
		#expect(parsed.isRekeyRequested)
		#expect(parsed.isAVUpgradable)
		#expect(parsed.participants[0].phoneJID == "15550002@s.whatsapp.net")
		#expect(parsed.participants[0].devices[0].pid == 0)
		#expect(parsed.relay?.transactionID == 1)
		#expect(parsed.relay?.warpTagLength == 16)
	}

	@Test("an ack's status decides whether its roster stands", arguments: [nil, "0", "207"])
	func ackStatuses(status: String?) throws {
		let parsed = try GroupCallUpdate.parse(offerAck: ack(error: status))
		#expect(parsed?.transactionID == 0)
		#expect(parsed?.connectedLimit == 0)
		#expect(parsed?.isRekeyRequested == true)
		#expect(parsed?.relay != nil)
	}

	@Test("any other ack status refuses the call")
	func ackRefused() {
		#expect(throws: GroupCallStanzaError.rejected("427")) {
			try GroupCallUpdate.parse(offerAck: ack(error: "427"))
		}
	}

	private func ack(error: String?) -> BinaryNode {
		BinaryNode(
			tag: "ack",
			attrs: BinaryNodeAttributes.trimmingUndefined([("class", "call"), ("type", "offer"), ("error", error)]),
			content: .nodes([
				BinaryNode(
					tag: "group_info",
					attrs: ["call-id": "CALL", "call-creator": "100001:1@lid", "media": "audio", "rekey": "1"],
					content: .nodes([BinaryNode(tag: "user", attrs: ["jid": "100001@lid", "state": "connected"])])
				),
				BinaryNode(tag: "relay", attrs: ["uuid": "U", "participant_uuid": "P"], content: .nodes([
					BinaryNode(tag: "key", content: .data(Data("k".utf8)))
				]))
			])
		)
	}

	@Test("forwarding envelopes unwrap only in the forms captured from real calls", arguments: [
		("0902336e0100018890e1001300120c96772e6aa9", "90e1001300120c96772e6aa9"),
		("09047eb5410001000000001090e100010013fbf08f1df407", "90e100010013fbf08f1df407"),
		("0907338f2900020a00c801e000000000000090780001000331808cd481d5", "90780001000331808cd481d5")
	])
	func unwrapsForwarding(packet: String, payload: String) throws {
		let unwrapped = try #require(CallRelayForwarding.unwrap(Data(hexString: packet)))
		#expect(hex(unwrapped) == payload)
	}

	@Test("an ordinary packet passes through, and an unknown envelope does not")
	func forwardingEdges() {
		let rtp = Data(hexString: "90e1001300120c96772e6aa9")
		#expect(CallRelayForwarding.unwrap(rtp) == rtp)
		#expect(CallRelayForwarding.unwrap(Data([0x09, 0x03, 0, 0, 0, 0, 0, 0])) == nil)
		#expect(CallRelayForwarding.unwrap(Data([0x09])) == nil)
		#expect(CallRelayForwarding.unwrap(Data([0x09, 0x02, 0, 0, 0, 0, 0, 0, 0x90])) == nil)
	}
}

@Suite("Group relay allocate")
struct GroupAllocateTests {
	private let streams = CallRelayAllocate.GroupStreams(
		ssrcs: [
			0x3ea2_6c0c, 0x0bf9_9b28, 0xf42e_4556,
			0x14e8_f126, 0xbb16_134f, 0x98b1_4f00,
			0xe0e0_4163, 0x74ed_8516, 0xdea8_a613
		],
		appData: 0xb31d_ed3e,
		hopByHopFEC: [0xc1a1_7938, 0x1bb2_0c84]
	)

	private func allocate(pids: [UInt32]) -> [CallSTUN.Attribute] {
		let request = CallRelayAllocate.groupRequest(
			transactionID: Data(0..<12),
			relayToken: Data([1, 2, 3]),
			relayIPv4: "10.0.0.1",
			relayPort: 3480,
			integrityKey: Data("0123456789abcdef".utf8),
			streams: streams,
			participantPIDs: pids
		)
		return CallSTUN.attributes(of: request ?? Data())
	}

	@Test("subscriptions and descriptors match bytes captured from a real client")
	func matchesCapture() {
		let attributes = allocate(pids: [2, 1, 2])
		#expect(attributes.map(\.type) == [
			CallSTUN.attributeRelayToken,
			CallSTUN.attributeSenderSubscriptions,
			CallSTUN.attributeReceiverSubscriptions,
			CallSTUN.attributeStreamDescriptors,
			CallSTUN.attributeParticipantCount,
			CallSTUN.attributeRelayEndpoint,
			CallSTUN.attributeMessageIntegrity
		])
		#expect(hex(attributes[1].value) == "0a1f0a1d0a0fa6e2a3a701cfa6d8d80b809ec5c5091204080110011204080210010a130a110a0fe38281870e968ab6a70793cca2f50d0a1a0a180a0e8cd889f503a8b6e65fd68ab9a10f12020801120208020a110a0f0a05bedaf7980b1202080112020802")
		#expect(hex(attributes[2].value) == "1202080112020802")
		#expect(hex(attributes[3].value) == "0a06188cd889f5030a07100118a8b6e65f0a08100218d68ab9a10f0a08080118a6e2a3a7010a0a0801100118cfa6d8d80b0a0a0801100218809ec5c5090a08080218e38281870e0a0a0802100118968ab6a7070a0a080210021893cca2f50d0a0a0803100318b8f2858d0c0a0a08041003188499c8dd01")
		#expect([UInt8](attributes[4].value) == [2])
	}

	@Test("one remote has no hop-by-hop FEC streams, and nobody leaves only the essentials")
	func smallerRosters() {
		#expect(allocate(pids: [1])[3].value == CallRelayAllocate.streamDescriptors(ssrcs: streams.ssrcs))
		#expect(allocate(pids: []).map(\.type) == [
			CallSTUN.attributeRelayToken,
			CallSTUN.attributeStreamDescriptors,
			CallSTUN.attributeRelayEndpoint,
			CallSTUN.attributeMessageIntegrity
		])
	}

	@Test("streams derive per participant except the secondary video trio, which is random and unique")
	func streamPlan() {
		var next: UInt32 = 0
		let plan = CallRelayAllocate.GroupStreams.make(callID: "CALL", participantID: "100001:1@lid") {
			next += 1
			return next
		}

		#expect(plan.ssrcs[0] == CallRelayAllocate.audioSSRC(callID: "CALL", participantID: "100001:1@lid"))
		#expect(plan.ssrcs[3] == CallRelayAllocate.videoSSRC(callID: "CALL", participantID: "100001:1@lid"))
		#expect(Array(plan.ssrcs[6..<9]) == [1, 2, 3])
		#expect(plan.appData == CallRelayAllocate.ssrc(callID: "CALL", participantID: "100001:1@lid", slot: 6))
	}
}

@Suite("Group call state")
struct GroupCallStateTests {
	private func state() -> GroupCallState {
		GroupCallState(callID: "CALL", callCreator: "100001:1@lid")
	}

	@Test("rosters are transaction ordered and replace each other whole")
	func ordering() {
		var state = state()
		#expect(state.apply(update(3, [participant("100001", pid: 0), participant("200002", pid: 1)])) == .applied)
		#expect(state.apply(update(3, [participant("100001", pid: 0)])) == .stale)
		#expect(state.snapshot?.participants.count == 2)
		#expect(state.apply(update(4, [participant("100001", pid: 0)])) == .applied)
		#expect(state.snapshot?.participants.count == 1)
	}

	@Test("a roster-only update keeps the relay and the PIDs it leaves out")
	func inheritance() {
		var state = state()
		#expect(state.apply(update(1, [participant("100001", pid: 0), participant("200002", pid: 1)], relay: relay(transaction: 1))) == .applied)
		#expect(state.apply(update(2, [
			participant("100001", pid: nil),
			participant("200002", pid: nil),
			participant("300003", pid: nil, state: "invited")
		])) == .applied)

		let pids = state.snapshot?.participants.map { $0.devices[0].pid }
		#expect(pids == [0, 1, nil])
		#expect(state.snapshot?.relay?.transactionID == 1)
	}

	@Test("a late relay is taken without moving the roster back")
	func lateRelay() {
		var state = state()
		#expect(state.apply(update(15, [participant("100001", pid: 0), participant("200002", pid: 1)])) == .applied)
		#expect(state.apply(update(13, [participant("100001", pid: 0)], relay: relay(transaction: 1))) == .relayOnly)
		#expect(state.snapshot?.transactionID == 15)
		#expect(state.snapshot?.participants.count == 2)
		#expect(state.snapshot?.relay?.transactionID == 1)
		#expect(state.apply(update(14, [participant("100001", pid: 0)], relay: relay(transaction: 0))) == .stale)
	}

	@Test("a PID may carry over across the PN and LID forms of one device, and no further")
	func aliasInheritance() {
		var state = state()
		var first = participant("200002", device: 3, pid: 5)
		first.phoneJID = "15550002@s.whatsapp.net"
		#expect(state.apply(update(1, [first])) == .applied)

		var aliased = GroupCallParticipant(
			jid: "200002@lid",
			phoneJID: "15550002@s.whatsapp.net",
			state: "connected",
			devices: [GroupCallDevice(jid: "15550002:3@s.whatsapp.net")]
		)
		#expect(state.apply(update(2, [aliased])) == .applied)
		#expect(state.snapshot?.participants[0].devices[0].pid == 5)
		#expect(state.snapshot?.participants[0].devices[0].jid == "15550002:3@s.whatsapp.net")

		aliased.devices = [GroupCallDevice(jid: "15550002:4@s.whatsapp.net")]
		#expect(state.apply(update(3, [aliased])) == .applied)
		#expect(state.snapshot?.participants[0].devices[0].pid == nil)
	}

	@Test("PID zero is real and PIDs stay unique")
	func pidZero() {
		var state = state()
		#expect(state.apply(update(1, [participant("100001", pid: 0), participant("200002", pid: 1)])) == .applied)
		#expect(state.apply(update(2, [participant("100001", pid: 0), participant("200002", pid: 0)])) == .invalid)
		#expect(state.snapshot?.transactionID == 1)
	}

	@Test("a reassigned PID colliding with an inherited one is refused without consuming the transaction")
	func inheritedCollision() {
		var state = state()
		#expect(state.apply(update(1, [participant("100001", pid: 0)])) == .applied)
		#expect(state.apply(update(2, [participant("100001", pid: nil), participant("200002", pid: 0)])) == .invalid)
		#expect(state.apply(update(2, [participant("100001", pid: nil), participant("200002", pid: 2)])) == .applied)
	}

	@Test("colliding media routes refuse the roster")
	func routeCollision() {
		let first = CallMediaCrypto.formatParticipantID("37774:1@lid")
		let second = CallMediaCrypto.formatParticipantID("53838:1@lid")
		#expect(CallRelayAllocate.audioSSRC(callID: "CALL", participantID: first)
			== CallRelayAllocate.audioSSRC(callID: "CALL", participantID: second))

		var state = state()
		#expect(state.apply(update(1, [participant("37774", pid: 1), participant("53838", pid: 2)])) == .invalid)
		#expect(state.apply(update(1, [participant("37774", pid: 1)])) == .applied)
	}

	@Test("malformed rosters are refused", arguments: [
		update(1, [], media: "text"),
		update(1, [], limit: 33),
		update(1, [participant("100001", pid: 0), participant("200002", pid: 1)], limit: 1),
		update(0, []),
		update(1, [], limit: 0)
	])
	func refused(snapshot: GroupCallUpdate) {
		var state = state()
		#expect(state.apply(snapshot) == .invalid)
		#expect(state.snapshot == nil)
	}

	@Test("a device cannot belong to someone else")
	func foreignDevice() {
		var mismatched = participant("100001", pid: 1)
		mismatched.devices[0].jid = "200002:1@lid"
		var state = state()
		#expect(state.apply(update(1, [mismatched])) == .invalid)
	}

	@Test("the call's group cannot change")
	func groupIdentity() {
		var state = state()
		#expect(state.apply(update(1, [], group: "1-1@g.us")) == .applied)
		#expect(state.apply(update(2, [])) == .applied)
		#expect(state.snapshot?.groupJID == "1-1@g.us")
		#expect(state.apply(update(3, [], group: "2-2@g.us")) == .identityMismatch)
		#expect(state.snapshot?.transactionID == 2)
	}

	@Test("the first snapshot may be an ack's partial one, and a later partial one is merely late")
	func partialAck() {
		var state = state()
		let ack = update(0, [participant("100001", pid: nil)], limit: 0)
		#expect(state.apply(ack) == .invalid)
		#expect(state.applyInitialOfferAck(ack) == .applied)
		#expect(state.apply(update(1, [participant("100001", pid: 0)])) == .applied)
		#expect(state.applyInitialOfferAck(ack) == .stale)
		#expect(state.snapshot?.transactionID == 1)
	}

	@Test("an overtaken ack still leaves its relay, without moving the roster or displacing a relay held")
	func overtakenAckRelay() {
		var state = state()
		#expect(state.apply(update(3, [participant("100001", pid: 0), participant("200002", pid: 1)])) == .applied)
		let ack = update(0, [participant("100001", pid: nil)], limit: 0, relay: relay(transaction: 1))
		#expect(state.applyInitialOfferAck(ack) == .stale)
		state.adoptRelayIfMissing(ack.relay)
		#expect(state.snapshot?.relay?.transactionID == 1)
		#expect(state.snapshot?.participants.count == 2)

		state.adoptRelayIfMissing(relay(transaction: 9))
		#expect(state.snapshot?.relay?.transactionID == 1)
	}

	@Test("a rekey the ack asked for waits for the first ordered roster, and is taken once")
	func owedRekey() {
		var state = state()
		#expect(state.applyInitialOfferAck(update(0, [participant("100001", pid: nil)], limit: 0, rekey: true)) == .applied)
		#expect(state.apply(update(1, [participant("100001", pid: 0)])) == .applied)
		let first = state.takeOwedRekey()
		let second = state.takeOwedRekey()
		#expect(first)
		#expect(!second)
	}
}

@Suite("Group media registry")
struct GroupMediaRegistryTests {
	private let epoch = Data(repeating: 0x42, count: 32)

	private func registry() -> CallGroupMediaRegistry {
		CallGroupMediaRegistry(callID: "CALL", callCreator: "100001:1@lid", localDevice: "100001:1@lid", tagLength: 4)
	}

	private func sender(_ device: String, key: Data) throws -> CallAudioPipeline {
		try CallAudioPipeline(
			callKey: key,
			selfParticipantID: device,
			peerParticipantID: "100001:1@lid",
			ssrc: CallRelayAllocate.audioSSRC(callID: "CALL", participantID: device)
		)
	}

	private func receive(_ registry: inout CallGroupMediaRegistry, _ packet: Data) throws -> (String, Data)? {
		let header = try #require(CallRTPHeader.parse(packet))
		guard let id = registry.participantID(forAudio: header.ssrc),
			  let received = try registry.unprotectAudio(packet, from: id) else {
			return nil
		}

		return (id, received.payload)
	}

	@Test("a key can arrive before its roster, and packets are told apart by sender")
	func futureEpoch() throws {
		var registry = registry()
		#expect(try registry.applyEpoch(transactionID: 7, key: epoch) == .buffered)
		#expect(try registry.apply(update(7, [
			participant("100001", pid: 0),
			participant("200002", pid: 1),
			participant("300003", pid: 2)
		])) == .applied)
		#expect(registry.installedEpoch?.transactionID == 7)
		#expect(registry.activePIDs == [1, 2])

		for device in ["200002:1@lid", "300003:1@lid"] {
			var pipeline = try sender(device, key: epoch)
			let received = try receive(&registry, pipeline.protect(Data([1, 2, 3])))
			#expect(received?.0 == device)
			#expect(received?.1 == Data([1, 2, 3]))
		}

		var stranger = try sender("400004:1@lid", key: epoch)
		#expect(try receive(&registry, stranger.protect(Data([1]))) == nil)
	}

	@Test("media waits for a key, and an old key does not open a new roster's participants")
	func keyless() throws {
		var registry = registry()
		_ = try registry.apply(update(1, [participant("100001", pid: 0), participant("200002", pid: 1)]))
		#expect(registry.activeParticipantIDs.isEmpty)

		var pipeline = try sender("200002:1@lid", key: epoch)
		#expect(try receive(&registry, pipeline.protect(Data([1]))) == nil)

		#expect(try registry.applyEpoch(transactionID: 1, key: epoch) == .installed)
		#expect(registry.activeParticipantIDs == ["200002:1@lid"])
	}

	@Test("someone who stays keeps their stream, and someone who leaves loses their route")
	func rosterChurn() throws {
		var registry = registry()
		_ = try registry.apply(update(2, [participant("100001", pid: 0), participant("200002", pid: 1)]))
		_ = try registry.applyEpoch(transactionID: 2, key: epoch)
		var pipeline = try sender("200002:1@lid", key: epoch)
		#expect(try receive(&registry, pipeline.protect(Data([1]))) != nil)

		_ = try registry.apply(update(3, [
			participant("100001", pid: 0),
			participant("200002", pid: 1),
			participant("300003", pid: 2)
		]))
		#expect(try receive(&registry, pipeline.protect(Data([2]))) != nil)

		_ = try registry.apply(update(4, [participant("100001", pid: 0)]))
		#expect(try receive(&registry, pipeline.protect(Data([3]))) == nil)
	}

	@Test("a new PID is a new session, whose sequence can start over")
	func pidMigration() throws {
		var registry = registry()
		_ = try registry.apply(update(1, [participant("100001", pid: 0), participant("200002", pid: 1)]))
		_ = try registry.applyEpoch(transactionID: 1, key: epoch)
		var first = try sender("200002:1@lid", key: epoch)
		_ = try first.protect(Data([1]))
		#expect(try receive(&registry, first.protect(Data([1]))) != nil)

		_ = try registry.apply(update(2, [participant("100001", pid: 0), participant("200002", pid: 9)]))
		var replacement = try sender("200002:1@lid", key: epoch)
		#expect(try receive(&registry, replacement.protect(Data([2]))) != nil)
	}

	@Test("a new key moves receiving to it, and the old one stops working")
	func rekey() throws {
		var registry = registry()
		_ = try registry.apply(update(1, [participant("100001", pid: 0), participant("200002", pid: 1)]))
		_ = try registry.applyEpoch(transactionID: 1, key: epoch)
		_ = try registry.apply(update(2, [participant("100001", pid: 0), participant("200002", pid: 1)]))
		let next = Data(repeating: 0x43, count: 32)
		#expect(try registry.applyEpoch(transactionID: 2, key: next) == .installed)

		var pipeline = try sender("200002:1@lid", key: epoch)
		#expect(throws: CallAudioPipeline.ReceiveError.authenticationFailed) {
			_ = try receive(&registry, pipeline.protect(Data([1])))
		}

		try pipeline.rekeySend(callKey: next, selfParticipantID: "200002:1@lid")
		#expect(try receive(&registry, pipeline.protect(Data([2]))) != nil)
	}

	@Test("repeated and conflicting keys are told apart")
	func epochConflicts() throws {
		var registry = registry()
		_ = try registry.apply(update(5, [participant("200002", pid: 1)]))
		#expect(try registry.applyEpoch(transactionID: 5, key: epoch) == .installed)
		#expect(try registry.applyEpoch(transactionID: 5, key: epoch) == .duplicate)
		#expect(throws: CallGroupMediaError.conflictingEpoch) {
			try registry.applyEpoch(transactionID: 5, key: Data(repeating: 1, count: 32))
		}
		#expect(try registry.applyEpoch(transactionID: 4, key: epoch) == .stale)
	}

	@Test("speculative future keys cannot push out the next real one")
	func epochBuffer() throws {
		var registry = registry()
		for transaction in UInt32(100)..<UInt32(100 + CallGroupMediaRegistry.maxBufferedEpochs) {
			#expect(try registry.applyEpoch(transactionID: transaction, key: epoch) == .buffered)
		}
		#expect(try registry.applyEpoch(transactionID: 1, key: epoch) == .buffered)
		_ = try registry.apply(update(1, [participant("200002", pid: 1)]))
		#expect(registry.installedEpoch?.transactionID == 1)
	}

	@Test("a seeded 1:1 peer stays heard through its first PID, and a roster without it removes it")
	func seededPeer() throws {
		var registry = registry()
		try registry.seedDirectPeer(callKey: epoch, userJID: "200002@lid", deviceJID: "200002:1@lid", video: true)
		var pipeline = try sender("200002:1@lid", key: epoch)
		#expect(try receive(&registry, pipeline.protect(Data([1]))) != nil)

		_ = try registry.apply(update(1, [participant("100001", pid: 0), participant("200002", pid: 1)]))
		#expect(try receive(&registry, pipeline.protect(Data([2]))) != nil)

		_ = try registry.apply(update(2, [participant("100001", pid: 0)]))
		#expect(try receive(&registry, pipeline.protect(Data([3]))) == nil)
	}

	@Test("a stale roster changes nothing")
	func staleRoster() throws {
		var registry = registry()
		_ = try registry.apply(update(5, [participant("100001", pid: 0), participant("200002", pid: 1)]))
		#expect(try registry.apply(update(4, [participant("100001", pid: 0)])) == .stale)
		#expect(registry.activePIDs == [1])
	}

	@Test("an offer ack's roster at transaction zero is taken once, and never over an ordered one")
	func transactionZero() throws {
		var registry = registry()
		let partial = update(0, [participant("100001", pid: nil)], limit: 0)
		#expect(try registry.apply(partial) == .applied)
		#expect(try registry.apply(partial) == .stale)
		#expect(try registry.apply(update(1, [participant("100001", pid: 0)])) == .applied)
		#expect(try registry.apply(partial) == .stale)
	}
}

@Suite("Group audio mixer")
struct GroupAudioMixerTests {
	private func frame(_ value: Int16, count: Int = 960) -> [Int16] {
		[Int16](repeating: value, count: count)
	}

	@Test("one speaker waits for two packets and then plays untouched")
	func prefill() {
		var mixer = CallGroupAudioMixer()
		mixer.push("a", frame(5))
		#expect(mixer.mixChunk() == nil)
		mixer.push("a", frame(5))
		#expect(mixer.mixChunk() == frame(5, count: CallGroupAudioMixer.chunkSamples))
	}

	@Test("speakers sum, and saturate instead of wrapping")
	func summing() {
		var mixer = CallGroupAudioMixer()
		for _ in 0..<2 {
			mixer.push("a", frame(30000))
			mixer.push("b", frame(10000))
		}
		#expect(mixer.mixChunk() == frame(Int16.max, count: CallGroupAudioMixer.chunkSamples))
	}

	@Test("a brief utterance plays out rather than waiting for later speech")
	func primingBound() {
		var mixer = CallGroupAudioMixer()
		mixer.push("a", frame(5, count: 320))
		for _ in 0..<(CallGroupAudioMixer.maxPrimeChunks - 1) {
			#expect(mixer.mixChunk() == nil)
		}
		#expect(mixer.mixChunk() != nil)
	}

	@Test("only the roster is heard, and leaving takes the queue along")
	func roster() {
		var mixer = CallGroupAudioMixer()
		mixer.push("a", frame(5))
		mixer.push("a", frame(5))
		mixer.retain(["b"])
		#expect(mixer.mixChunk() == nil)
		let departed = mixer.push("a", frame(5))
		mixer.push("b", frame(5))
		let present = mixer.push("b", frame(5))
		#expect(!departed)
		#expect(present)
		#expect(mixer.mixChunk() != nil)
	}

	@Test("the queue is bounded, dropping the oldest to keep to real time")
	func overflow() {
		var mixer = CallGroupAudioMixer()
		mixer.push("a", frame(1, count: 960))
		for _ in 0..<4 {
			mixer.push("a", frame(2, count: 960))
		}
		#expect(mixer.mixChunk() == frame(2, count: CallGroupAudioMixer.chunkSamples))
	}

	@Test("a long packet gets a cushion of its own size")
	func longPackets() {
		var mixer = CallGroupAudioMixer()
		mixer.push("a", frame(1, count: 1920))
		#expect(mixer.mixChunk() == nil)
		mixer.push("a", frame(1, count: 1920))
		#expect(mixer.mixChunk() != nil)
	}
}

// MARK: - Sessions over a fake group relay

/// A selective forwarding relay in memory: answers Allocate and passes each participant's media to the
/// others inside the forwarding envelope a real relay uses.
private actor FakeGroupRelay {
	private var legs: [Int: AsyncStream<Data>.Continuation] = [:]
	private(set) var allocates = [Data]()

	func register(_ leg: Int, _ continuation: AsyncStream<Data>.Continuation) {
		legs[leg] = continuation
	}

	func receive(from leg: Int, _ message: Data) {
		if CallSTUN.isSTUN(message) {
			if CallSTUN.messageType(message) == CallSTUN.allocateRequest {
				allocates.append(message)
				let transaction = CallSTUN.transactionID(message) ?? Data(count: 12)
				legs[leg]?.yield(CallSTUN.encode(type: CallSTUN.allocateSuccess, transactionID: transaction))
			}
			return
		}

		let envelope = Data([0x09, 0x02, 0x33, 0x6e, 0x01, 0x00, 0x01, 0x88])
		for (other, continuation) in legs where other != leg {
			continuation.yield(envelope + message)
		}
	}
}

private final class FakeGroupLink: CallRelayLink, @unchecked Sendable {
	let messages: AsyncStream<Data>
	private let continuation: AsyncStream<Data>.Continuation
	private let relay: FakeGroupRelay
	private let leg: Int

	init(relay: FakeGroupRelay, leg: Int) async {
		(messages, continuation) = AsyncStream.makeStream()
		self.relay = relay
		self.leg = leg
		await relay.register(leg, continuation)
	}

	func open() async throws {}

	func send(_ message: Data) async throws {
		await relay.receive(from: leg, message)
	}

	func close() async {
		continuation.finish()
	}
}

@Suite("Group call sessions", .serialized)
struct GroupCallSessionTests {
	private let alice = "100001:1@lid"
	private let bob = "200002:1@lid"
	private let carol = "300003:1@lid"
	private let key = Data(repeating: 0x42, count: 32)

	private func roster(transaction: UInt32 = 1, media: String = "video", rekey: Bool = false) -> GroupCallUpdate {
		update(
			transaction,
			[participant("100001", pid: 0), participant("200002", pid: 1), participant("300003", pid: 2)],
			media: media,
			rekey: rekey,
			relay: relay(transaction: 1)
		)
	}

	private func session(_ me: String, leg: Int, relay fake: FakeGroupRelay, roster: GroupCallUpdate) async throws -> CallSession {
		try await CallSession(
			configuration: CallSession.Configuration(
				callID: "CALL",
				selfParticipantID: me,
				peerParticipantID: me,
				callKey: Data(count: 32),
				relay: try #require(roster.relay),
				groupUpdate: roster
			),
			link: FakeGroupLink(relay: fake, leg: leg)
		)
	}

	private func tone() -> [Int16] {
		(0..<960).map { Int16(8000 * sin(Double($0) * 0.1)) }
	}

	@Test("media is held back until a key arrives, then flows to each participant and mixes")
	func audioFlows() async throws {
		let fake = FakeGroupRelay()
		let snapshot = roster()
		let a = try await session(alice, leg: 0, relay: fake, roster: snapshot)
		let b = try await session(bob, leg: 1, relay: fake, roster: snapshot)
		let c = try await session(carol, leg: 2, relay: fake, roster: snapshot)
		try await a.start()
		try await b.start()
		try await c.start()

		try await b.sendAudio(tone())
		try await Task.sleep(for: .milliseconds(100))
		#expect(await a.framesReceived == 0)
		#expect(await b.framesSent == 0)

		let epoch = GroupCallEpoch(transactionID: 1, key: key)
		for session in [a, b, c] {
			try await session.applyGroupEpoch(epoch)
		}

		for _ in 0..<4 {
			try await b.sendAudio(tone())
			try await c.sendAudio(tone())
		}

		let mixed = try await withThrowingTaskGroup(of: [Int16]?.self) { tasks in
			tasks.addTask {
				for await frame in a.receivedAudio where frame.contains(where: { $0 != 0 }) {
					return frame
				}
				return nil
			}
			tasks.addTask {
				try await Task.sleep(for: .seconds(5))
				return nil
			}
			let first = try await tasks.next() ?? nil
			tasks.cancelAll()
			return first
		}

		#expect(mixed != nil)
		#expect(await a.framesReceived == 8)
		#expect(await a.keysRejected == 0)
		await a.stop()
		await b.stop()
		await c.stop()
	}

	@Test("pictures arrive labeled with who sent them")
	func videoIsLabeled() async throws {
		let fake = FakeGroupRelay()
		let snapshot = roster()
		let a = try await session(alice, leg: 0, relay: fake, roster: snapshot)
		let b = try await session(bob, leg: 1, relay: fake, roster: snapshot)
		try await a.start()
		try await b.start()
		let epoch = GroupCallEpoch(transactionID: 1, key: key)
		try await a.applyGroupEpoch(epoch)
		try await b.applyGroupEpoch(epoch)

		await b.setVideoSending(true)
		let accessUnit = Data([0, 0, 0, 1, 0x65, 0x88, 0x84, 0x21])
		try await b.sendVideo(accessUnit, timestamp: 90_000)

		var iterator = a.receivedParticipantVideo.makeAsyncIterator()
		let frame = await iterator.next()
		#expect(frame?.participantID == bob)
		#expect(frame?.frame.isKeyframe == true)
		await a.stop()
		await b.stop()
	}

	@Test("a roster that adds someone subscribes to them with a new Allocate, and asks for a keyframe")
	func rosterChangeReallocates() async throws {
		let fake = FakeGroupRelay()
		let first = update(
			1,
			[participant("100001", pid: 0), participant("200002", pid: 1)],
			relay: relay(transaction: 1)
		)
		let a = try await session(alice, leg: 0, relay: fake, roster: first)
		try await a.start()
		try await a.applyGroupEpoch(GroupCallEpoch(transactionID: 1, key: key))
		let before = await fake.allocates.count

		await a.setVideoSending(true)
		var events = a.videoSendEvents.makeAsyncIterator()
		_ = await events.next()
		try await a.sendVideo(Data([0, 0, 0, 1, 0x65, 0x88]), timestamp: 90_000)

		try await a.applyGroupUpdate(roster(transaction: 2))
		#expect(await fake.allocates.count > before)
		let last = await fake.allocates.last
		let attributes = CallSTUN.attributes(of: last ?? Data())
		#expect(attributes.first { $0.type == CallSTUN.attributeParticipantCount }?.value == Data([2]))
		#expect(await events.next() == .keyframeNeeded)
		await a.stop()
	}

	@Test("a requested key stops media until it arrives")
	func requestedKeyGates() async throws {
		let fake = FakeGroupRelay()
		let snapshot = roster()
		let a = try await session(alice, leg: 0, relay: fake, roster: snapshot)
		try await a.start()
		try await a.applyGroupEpoch(GroupCallEpoch(transactionID: 1, key: key))
		try await a.sendAudio(tone())
		#expect(await a.framesSent == 1)

		try await a.applyGroupUpdate(roster(transaction: 2, rekey: true))
		try await a.sendAudio(tone())
		#expect(await a.framesSent == 1)

		try await a.applyGroupEpoch(GroupCallEpoch(transactionID: 2, key: Data(repeating: 0x43, count: 32)))
		try await a.sendAudio(tone())
		#expect(await a.framesSent == 2)
		await a.stop()
	}

	@Test("a roster without this device ends it")
	func removed() async throws {
		let fake = FakeGroupRelay()
		let a = try await session(alice, leg: 0, relay: fake, roster: roster())
		try await a.start()
		await #expect(throws: CallGroupMediaError.localParticipantRemoved) {
			try await a.applyGroupUpdate(update(2, [participant("200002", pid: 1)]))
		}
		await a.stop()
	}

	@Test("a 1:1 call becomes a group call in place, and its peer stays heard on the call key")
	func promotion() async throws {
		let fake = FakeGroupRelay()
		let relayBlock = relay(transaction: 1)
		let a = try await CallSession(
			configuration: CallSession.Configuration(
				callID: "CALL", selfParticipantID: alice, peerParticipantID: bob, callKey: key, relay: relayBlock
			),
			link: FakeGroupLink(relay: fake, leg: 0)
		)
		let b = try await CallSession(
			configuration: CallSession.Configuration(
				callID: "CALL", selfParticipantID: bob, peerParticipantID: alice, callKey: key, relay: relayBlock
			),
			link: FakeGroupLink(relay: fake, leg: 1)
		)
		try await a.start()
		try await b.start()

		try await a.applyGroupUpdate(update(1, [participant("100001", pid: 0), participant("200002", pid: 1)]))
		#expect(await a.isGroupCall)

		for _ in 0..<2 {
			try await b.sendAudio(tone())
		}
		try await Task.sleep(for: .milliseconds(150))
		#expect(await a.framesReceived == 2)
		await a.stop()
		await b.stop()
	}

	@Test("a 1:1 call is unaffected: it still reads its peer directly, envelope or not")
	func directUnaffected() async throws {
		let fake = FakeGroupRelay()
		let relayBlock = relay(transaction: nil)
		let a = try await CallSession(
			configuration: CallSession.Configuration(
				callID: "CALL", selfParticipantID: alice, peerParticipantID: bob, callKey: key, relay: relayBlock
			),
			link: FakeGroupLink(relay: fake, leg: 0)
		)
		let b = try await CallSession(
			configuration: CallSession.Configuration(
				callID: "CALL", selfParticipantID: bob, peerParticipantID: alice, callKey: key, relay: relayBlock
			),
			link: FakeGroupLink(relay: fake, leg: 1)
		)
		try await a.start()
		try await b.start()
		try await b.sendAudio(tone())

		var frames = a.receivedAudio.makeAsyncIterator()
		#expect(await frames.next() != nil)
		#expect(await a.isGroupCall == false)
		await a.stop()
		await b.stop()
	}
}

// MARK: - Client

@Suite("Group call stanzas in the client")
struct GroupCallClientTests {
	private func client() -> WhatsAppClient {
		WhatsAppClient(authenticationState: nil, transportFactory: { _ in MockMessageSendWebSocketTransport() })
	}

	private func groupOffer() -> BinaryNode {
		BinaryNode(
			tag: "call",
			attrs: ["from": "100001:1@lid", "id": "s1", "t": "1"],
			content: .nodes([BinaryNode(
				tag: "offer",
				attrs: ["call-id": "CALL", "call-creator": "100001:1@lid", "joinable": "1"],
				content: .nodes([
					BinaryNode(tag: "audio", attrs: ["enc": "opus", "rate": "16000"]),
					rosterInfo(transaction: 7, users: [("100001", "connected")])
				])
			)])
		)
	}

	private func rosterInfo(transaction: UInt32, users: [(String, String)]) -> BinaryNode {
		BinaryNode(
			tag: "group_info",
			attrs: ["transaction-id": String(transaction), "connected-limit": "32", "media": "audio", "joinable": "1"],
			content: .nodes(users.map { user, state in
				BinaryNode(
					tag: "user",
					attrs: ["jid": "\(user)@lid", "state": state],
					content: .nodes([BinaryNode(tag: "device", attrs: ["jid": "\(user):1@lid"])])
				)
			})
		)
	}

	private func stanza(_ tag: String, from: String = "100001:1@lid", participant: String? = nil, children: [BinaryNode] = []) -> BinaryNode {
		BinaryNode(
			tag: "call",
			attrs: BinaryNodeAttributes.trimmingUndefined([("from", from), ("id", "s2"), ("t", "2"), ("participant", participant)]),
			content: .nodes([BinaryNode(
				tag: tag,
				attrs: ["call-id": "CALL", "call-creator": "100001:1@lid"],
				content: .nodes(children)
			)])
		)
	}

	@Test("an offer with a roster is a group call, and its roster is held")
	func offerIsGroup() async {
		let client = client()
		_ = await client.handleCallNode(groupOffer())

		#expect(await client.callOfferCache["CALL"]?.isGroup == true)
		#expect(await client.groupCallSnapshot(id: "CALL")?.transactionID == 7)
	}

	@Test("someone else answering or declining leaves a group call ringing here", arguments: ["accept", "reject"])
	func othersKeepItRinging(action: String) async {
		let client = client()
		_ = await client.handleCallNode(groupOffer())
		_ = await client.handleCallNode(stanza(action, participant: "200002:1@lid"))

		#expect(await client.callOfferNodes["CALL"] != nil)
	}

	@Test("only the creator or the service can end the call for everyone")
	func terminateAuthority() async {
		let client = client()
		_ = await client.handleCallNode(groupOffer())

		_ = await client.handleCallNode(stanza("terminate", from: "CALL@call", participant: "200002:1@lid"))
		#expect(await client.callOfferNodes["CALL"] != nil)

		_ = await client.handleCallNode(stanza("terminate", from: "CALL@call"))
		#expect(await client.callOfferNodes["CALL"] == nil)
		#expect(await client.groupCallSnapshot(id: "CALL") == nil)
	}

	@Test("a key alone does not make a 1:1 call a group call, so its peer can still hang up")
	func strayKeyKeepsDirectTerminate() async {
		let client = client()
		await client.storeGroupCallRecord(
			GroupCallRecord(state: GroupCallState(callID: "CALL", callCreator: "100001:1@lid")),
			for: "CALL"
		)
		_ = await client.handleCallNode(stanza("offer"))
		_ = await client.handleCallNode(stanza("terminate", participant: "200002:1@lid"))

		#expect(await client.callOfferNodes["CALL"] == nil)
	}

	@Test("a roster from an outsider is ignored, and the service's is committed")
	func rosterAuthority() async {
		let client = client()
		_ = await client.handleCallNode(groupOffer())

		let info = rosterInfo(transaction: 8, users: [("100001", "connected"), ("200002", "connected")])
		_ = await client.handleCallNode(stanza("group_update", from: "CALL@call", participant: "900009:1@lid", children: [info]))
		#expect(await client.groupCallSnapshot(id: "CALL")?.transactionID == 7)

		_ = await client.handleCallNode(stanza("group_update", from: "CALL@call", children: [info]))
		#expect(await client.groupCallSnapshot(id: "CALL")?.transactionID == 8)
	}

	@Test("the roster reaches the app as an event")
	func rosterEvent() async throws {
		let client = client()
		let events = await client.events
		_ = await client.handleCallNode(stanza(
			"group_update",
			children: [rosterInfo(transaction: 3, users: [("100001", "connected")])]
		))

		for await event in events {
			if case let .call(calls) = event, let call = calls.first(where: { $0.status == .groupUpdate }) {
				#expect(call.groupUpdate?.transactionID == 3)
				#expect(call.isGroup == true)
				break
			}
		}
	}

	@Test("a notice cannot be answered")
	func notice() async throws {
		let client = client()
		let events = await client.events
		_ = await client.handleCallNode(BinaryNode(
			tag: "call",
			attrs: ["from": "100001:1@lid", "id": "s", "t": "1"],
			content: .nodes([BinaryNode(
				tag: "offer_notice",
				attrs: ["call-id": "CALL", "call-creator": "100001:1@lid", "type": "group", "media": "video"]
			)])
		))

		for await event in events {
			if case let .call(calls) = event, let call = calls.first {
				#expect(call.isNotice)
				#expect(call.isGroup == true)
				#expect(call.isVideo == true)
				break
			}
		}
	}
}

private extension Data {
	init(hexString: String) {
		var bytes = [UInt8]()
		var index = hexString.startIndex
		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			bytes.append(UInt8(hexString[index..<next], radix: 16) ?? 0)
			index = next
		}
		self.init(bytes)
	}
}
