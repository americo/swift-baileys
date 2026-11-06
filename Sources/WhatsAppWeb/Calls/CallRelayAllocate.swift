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

	/// Stream descriptors protobuf (`StreamDescriptors`, attribute 0x4024) for this call's streams.
	public static func streamDescriptors(callID: String, participantID: String) -> Data {
		var out = [UInt8]()
		for slot in streamSlots {
			let value = ssrc(callID: callID, participantID: participantID, slot: slot.slot)
			guard value != 0 else {
				continue
			}

			var descriptor = [UInt8]()
			if slot.stream != 0 {
				descriptor += protobufTag(field: 1, wire: 0) + varint(slot.stream)
			}
			if slot.subType != 0 {
				descriptor += protobufTag(field: 2, wire: 0) + varint(slot.subType)
			}
			descriptor += protobufTag(field: 3, wire: 0) + varint(UInt64(value))
			out += protobufTag(field: 1, wire: 2) + varint(UInt64(descriptor.count)) + descriptor
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
}
