import Foundation

/// Per-call stream identifiers and the relay Allocate request that registers them.
public enum CallRelayAllocate {
	/// Relay stream slots as `(stream index, sub-type, slot word)`, in wire order. Stream indices
	/// are audio / video / secondary video; sub-types are media / FEC / NACK.
	static let streamSlots: [(stream: UInt64, subType: UInt64, slot: UInt32)] = [
		(0, 0, 0), (0, 1, 1), (0, 2, 4),
		(1, 0, 2), (1, 1, 3), (1, 2, 5),
		(2, 0, 7), (2, 1, 8), (2, 2, 6)
	]

	public static let audioSlot: UInt32 = 0
	public static let videoSlot: UInt32 = 2

	/// SSRC of a participant's stream: HKDF-SHA256 with the call id as input key material, the slot
	/// word (little-endian) as salt and the participant id as info, read back little-endian.
	public static func ssrc(callID: String, participantID: String, slot: UInt32) -> UInt32 {
		let okm = CallMediaCrypto.hkdfSHA256(
			salt: Data(littleEndian(slot)),
			inputKeyMaterial: Data(callID.utf8),
			info: Data(participantID.utf8),
			length: 4
		)
		return okm.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << UInt32(8 * $1.offset) }
	}

	public static func audioSSRC(callID: String, participantID: String) -> UInt32 {
		ssrc(callID: callID, participantID: participantID, slot: audioSlot)
	}

	public static func videoSSRC(callID: String, participantID: String) -> UInt32 {
		ssrc(callID: callID, participantID: participantID, slot: videoSlot)
	}

	/// Stream descriptors protobuf (`StreamDescriptors`, attribute 0x4024) for this call's streams.
	public static func streamDescriptors(callID: String, participantID: String) -> Data {
		streamDescriptors(ssrcs: streamSlots.map { ssrc(callID: callID, participantID: participantID, slot: $0.slot) })
	}

	/// Descriptors for an explicit set of SSRCs, in `streamSlots` order. `hopByHopFEC` adds the two
	/// extra streams of a call subscribed to more than one participant.
	static func streamDescriptors(ssrcs: [UInt32], hopByHopFEC: [UInt32] = []) -> Data {
		var out = [UInt8]()
		func append(stream: UInt64, subType: UInt64, value: UInt32) {
			guard value != 0 else {
				return
			}

			var descriptor = [UInt8]()
			if stream != 0 {
				descriptor += protobufTag(field: 1, wire: 0) + varint(stream)
			}
			if subType != 0 {
				descriptor += protobufTag(field: 2, wire: 0) + varint(subType)
			}
			descriptor += protobufTag(field: 3, wire: 0) + varint(UInt64(value))
			out += lengthDelimited(field: 1, descriptor)
		}

		for (slot, value) in zip(streamSlots, ssrcs) {
			append(stream: slot.stream, subType: slot.subType, value: value)
		}
		for (index, value) in hopByHopFEC.enumerated() {
			append(stream: UInt64(index + 3), subType: 3, value: value)
		}

		return Data(out)
	}

	/// Allocate request in the WhatsApp Web shape: relay token, stream descriptors and the XOR relay
	/// endpoint, signed with MESSAGE-INTEGRITY and without FINGERPRINT.
	public static func request(
		transactionID: Data,
		relayToken: Data,
		relayIPv4: String,
		relayPort: UInt16,
		integrityKey: Data,
		callID: String,
		participantID: String
	) -> Data? {
		guard let endpoint = CallSTUN.xorRelayEndpoint(ipv4: relayIPv4, port: relayPort) else {
			return nil
		}

		var attributes = CallSTUN.attribute(CallSTUN.attributeRelayToken, relayToken)
		attributes.append(CallSTUN.attribute(
			CallSTUN.attributeStreamDescriptors,
			streamDescriptors(callID: callID, participantID: participantID)
		))
		attributes.append(CallSTUN.attribute(CallSTUN.attributeRelayEndpoint, Data([0x00, 0x01]) + endpoint))
		return CallSTUN.encode(
			type: CallSTUN.allocateRequest,
			transactionID: transactionID,
			attributes: attributes,
			integrityKey: integrityKey
		)
	}

	// MARK: Group calls

	/// The streams one device announces to a group relay.
	public struct GroupStreams: Equatable, Sendable {
		/// In `streamSlots` order. The secondary-video trio is random rather than derived.
		public let ssrcs: [UInt32]
		public let appData: UInt32
		public let hopByHopFEC: [UInt32]

		public init(ssrcs: [UInt32], appData: UInt32, hopByHopFEC: [UInt32]) {
			self.ssrcs = ssrcs
			self.appData = appData
			self.hopByHopFEC = hopByHopFEC
		}

		/// Derives them for one call. `random` is injected so tests are repeatable.
		public static func make(
			callID: String,
			participantID: String,
			random: () -> UInt32 = { UInt32.random(in: 1...UInt32.max) }
		) -> GroupStreams {
			var ssrcs = streamSlots.map { ssrc(callID: callID, participantID: participantID, slot: $0.slot) }
			let appData = ssrc(callID: callID, participantID: participantID, slot: appDataSlot)
			var used = Set(ssrcs.prefix(6))
			used.insert(appData)
			for index in 6..<ssrcs.count {
				var candidate = random()
				while candidate == 0 || !used.insert(candidate).inserted {
					candidate = random()
				}
				ssrcs[index] = candidate
			}

			return GroupStreams(
				ssrcs: ssrcs,
				appData: appData,
				hopByHopFEC: hopByHopFECSlots.map { ssrc(callID: callID, participantID: participantID, slot: $0) }
			)
		}
	}

	public static let appDataSlot: UInt32 = 6
	static let hopByHopFECSlots: [UInt32] = [7, 8]

	/// Allocate request for a group relay. Besides what a 1:1 call registers, it subscribes this device
	/// to the media of each remote PID, and offers its own to them.
	public static func groupRequest(
		transactionID: Data,
		relayToken: Data,
		relayIPv4: String,
		relayPort: UInt16,
		integrityKey: Data,
		streams: GroupStreams,
		participantPIDs: [UInt32]
	) -> Data? {
		guard let endpoint = CallSTUN.xorRelayEndpoint(ipv4: relayIPv4, port: relayPort) else {
			return nil
		}

		let pids = Array(Set(participantPIDs)).sorted()
		var attributes = CallSTUN.attribute(CallSTUN.attributeRelayToken, relayToken)
		if !pids.isEmpty {
			attributes.append(CallSTUN.attribute(
				CallSTUN.attributeSenderSubscriptions,
				senderSubscriptions(streams: streams, pids: pids)
			))
			attributes.append(CallSTUN.attribute(CallSTUN.attributeReceiverSubscriptions, receiverSubscriptions(pids: pids)))
		}
		attributes.append(CallSTUN.attribute(
			CallSTUN.attributeStreamDescriptors,
			streamDescriptors(ssrcs: streams.ssrcs, hopByHopFEC: pids.count > 1 ? streams.hopByHopFEC : [])
		))
		if !pids.isEmpty {
			attributes.append(CallSTUN.attribute(CallSTUN.attributeParticipantCount, Data(varint(UInt64(pids.count)))))
		}
		attributes.append(CallSTUN.attribute(CallSTUN.attributeRelayEndpoint, Data([0x00, 0x01]) + endpoint))
		return CallSTUN.encode(
			type: CallSTUN.allocateRequest,
			transactionID: transactionID,
			attributes: attributes,
			integrityKey: integrityKey
		)
	}

	/// Who receives this device's video, its secondary video (nobody), its audio and its app data.
	static func senderSubscriptions(streams: GroupStreams, pids: [UInt32]) -> Data {
		Data(
			senderSubscription(Array(streams.ssrcs[3..<6]), pids: pids, isVideo: true)
				+ senderSubscription(Array(streams.ssrcs[6..<9]), pids: [], isVideo: false)
				+ senderSubscription(Array(streams.ssrcs[0..<3]), pids: pids, isVideo: false)
				+ senderSubscription([streams.appData], pids: pids, isVideo: false)
		)
	}

	static func receiverSubscriptions(pids: [UInt32]) -> Data {
		Data(pids.flatMap { pid in
			lengthDelimited(field: 2, protobufTag(field: 1, wire: 0) + varint(UInt64(pid)))
		})
	}

	private static func senderSubscription(_ ssrcs: [UInt32], pids: [UInt32], isVideo: Bool) -> [UInt8] {
		var subscription = lengthDelimited(field: 1, ssrcs.filter { $0 != 0 }.flatMap { varint(UInt64($0)) })
		for pid in pids {
			var participant = protobufTag(field: 1, wire: 0) + varint(UInt64(pid))
			if isVideo {
				participant += protobufTag(field: 2, wire: 0) + varint(1)
			}
			subscription += lengthDelimited(field: 2, participant)
		}

		return lengthDelimited(field: 1, lengthDelimited(field: 1, subscription))
	}

	private static func lengthDelimited(field: UInt64, _ bytes: [UInt8]) -> [UInt8] {
		protobufTag(field: field, wire: 2) + varint(UInt64(bytes.count)) + bytes
	}

	private static func littleEndian(_ value: UInt32) -> [UInt8] {
		(0..<4).map { UInt8(truncatingIfNeeded: value >> UInt32(8 * $0)) }
	}

	private static func protobufTag(field: UInt64, wire: UInt64) -> [UInt8] {
		varint(field << 3 | wire)
	}

	private static func varint(_ value: UInt64) -> [UInt8] {
		var remaining = value
		var out = [UInt8]()
		while remaining > 0x7f {
			out.append(UInt8(remaining & 0x7f) | 0x80)
			remaining >>= 7
		}
		out.append(UInt8(remaining))
		return out
	}
}

extension CallSTUN {
	public static let attributeStreamDescriptors: UInt16 = 0x4024
	public static let attributeRelayEndpoint: UInt16 = 0x0016
	public static let attributeSenderSubscriptions: UInt16 = 0x4025
	public static let attributeReceiverSubscriptions: UInt16 = 0x4021
	public static let attributeParticipantCount: UInt16 = 0x805a
}
