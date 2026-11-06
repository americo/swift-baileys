import Foundation

/// Capability blobs advertised in call stanzas. Bit 31 of the mask is `use_mlow_codec_v1`; the
/// "standard Opus" variants clear it so the peer sends plain Opus instead of the proprietary MLow.
public enum CallCapability {
	public static let offer = Data([0x01, 0x05, 0xf7, 0x09, 0xe0, 0xbb, 0x13])
	public static let preaccept = Data([0x01, 0x05, 0xf7, 0x09, 0xe0, 0xbb, 0x07])
	public static let standardOpusOffer = clearingMLow(offer)
	public static let standardOpusPreaccept = clearingMLow(preaccept)

	/// Index of the MLow bit inside the mask that follows the two-byte `[version][length]` header.
	static let mlowIndex = 31

	static func clearingMLow(_ blob: Data) -> Data {
		var copy = blob
		let position = 2 + mlowIndex / 8
		guard copy.count > position else {
			return copy
		}

		copy[copy.startIndex + position] &= ~UInt8(1 << (mlowIndex % 8))
		return copy
	}
}

/// `<voip_settings>` payloads that force the peer's decoder onto standard Opus.
public enum CallVoIPSettings {
	public static let standardOpus16kHzClock = Data(
		#"{"encode":{"use_mlow_codec_v1":"false"},"options":{"enable_48khz_rtp_clock":"false"}}"#.utf8
	)
	public static let standardOpus48kHzClock = Data(
		#"{"encode":{"use_mlow_codec_v1":"false"},"options":{"enable_48khz_rtp_clock":"true"}}"#.utf8
	)
}

public struct CallOfferDeviceKey: Equatable, Sendable {
	public let deviceJID: String
	public let ciphertext: Data
	/// Signal message type: `pkmsg` or `msg`.
	public let encryptionType: String

	public init(deviceJID: String, ciphertext: Data, encryptionType: String) {
		self.deviceJID = deviceJID
		self.ciphertext = ciphertext
		self.encryptionType = encryptionType
	}
}

/// Builders for the `<call>` stanzas of a 1:1 voice call. Child order matters: the server rejects
/// out-of-order children, so each builder follows the order the official client sends.
public enum CallStanzaBuilder {
	/// One `<audio>` per offered rate. WhatsApp selects its audio path by this rate, and the 16 kHz
	/// Opus this library sends and receives is signaled as 16000 alone.
	public static let defaultAudioRates = ["16000"]
	public static let rejectReasonBusy = "busy"
	/// The device could not decrypt the offer. Like `busy`, this speaks for that device only.
	public static let rejectReasonEnc = "enc"
	public static let terminateReasonAcceptedElsewhere = "accepted_elsewhere"

	/// `<offer>`: privacy → audio… → net → capability → destination|enc → encopt → device-identity.
	public static func offer(
		callID: String,
		to: String,
		callCreator: String,
		stanzaID: String,
		deviceKeys: [CallOfferDeviceKey],
		privacyToken: Data? = nil,
		capability: Data = CallCapability.standardOpusOffer,
		deviceIdentity: Data? = nil,
		multiDevice: Bool = false,
		audioRates: [String] = defaultAudioRates
	) -> BinaryNode {
		var children = [BinaryNode]()
		if let privacyToken {
			children.append(BinaryNode(tag: "privacy", content: .data(privacyToken)))
		}
		children += audioRates.map(audioNode)
		children.append(BinaryNode(tag: "net", attrs: ["medium": "3"]))
		children.append(capabilityNode(capability))

		if deviceKeys.count > 1 || multiDevice {
			let destinations = deviceKeys.map { key in
				BinaryNode(tag: "to", attrs: ["jid": key.deviceJID], content: .nodes([encNode(key)]))
			}
			children.append(BinaryNode(tag: "destination", content: .nodes(destinations)))
		} else if let key = deviceKeys.first {
			children.append(encNode(key))
		}

		children.append(encoptNode)
		if let deviceIdentity {
			children.append(BinaryNode(tag: "device-identity", content: .data(deviceIdentity)))
		}

		return wrap(to: to, stanzaID: stanzaID, action: action("offer", callID, callCreator, children))
	}

	/// `<preaccept>`: audio… → encopt → capability. Sent by the callee while the user decides.
	public static func preaccept(
		callID: String,
		to: String,
		callCreator: String,
		stanzaID: String,
		capability: Data = CallCapability.standardOpusPreaccept,
		audioRates: [String] = defaultAudioRates
	) -> BinaryNode {
		let children = audioRates.map(audioNode) + [encoptNode, capabilityNode(capability)]
		return wrap(to: to, stanzaID: stanzaID, action: action("preaccept", callID, callCreator, children))
	}

	/// `<accept>`: audio… → [te] → net → encopt → capability → [rte] → voip_settings.
	public static func accept(
		callID: String,
		to: String,
		callCreator: String,
		stanzaID: String,
		relayTransportEndpoint: Data? = nil,
		routingToken: Data? = nil,
		voipSettings: Data? = CallVoIPSettings.standardOpus16kHzClock,
		capability: Data = CallCapability.standardOpusOffer,
		audioRates: [String] = defaultAudioRates
	) -> BinaryNode {
		var children = audioRates.map(audioNode)
		if let relayTransportEndpoint {
			children.append(BinaryNode(tag: "te", attrs: ["priority": "2"], content: .data(relayTransportEndpoint)))
		}
		children.append(BinaryNode(tag: "net", attrs: ["medium": "2"]))
		children.append(encoptNode)
		children.append(capabilityNode(capability))
		if let routingToken {
			children.append(BinaryNode(tag: "rte", content: .data(routingToken)))
		}
		if let voipSettings {
			children.append(BinaryNode(
				tag: "voip_settings",
				attrs: ["uncompressed": "1"],
				content: .data(voipSettings)
			))
		}

		return wrap(to: to, stanzaID: stanzaID, action: action("accept", callID, callCreator, children))
	}

	public static func reject(
		callID: String,
		to: String,
		callCreator: String,
		stanzaID: String,
		reason: String? = nil
	) -> BinaryNode {
		var attrs: BinaryNodeAttributes = ["call-id": callID, "call-creator": callCreator, "count": "0"]
		if let reason {
			attrs = BinaryNodeAttributes(attrs.orderedEntries + [("reason", reason)])
		}

		return wrap(to: to, stanzaID: stanzaID, action: BinaryNode(tag: "reject", attrs: attrs))
	}

	public static func terminate(
		callID: String,
		to: String,
		callCreator: String,
		stanzaID: String,
		reason: String? = nil
	) -> BinaryNode {
		var attrs: BinaryNodeAttributes = ["call-id": callID, "call-creator": callCreator]
		if let reason {
			attrs = BinaryNodeAttributes(attrs.orderedEntries + [("reason", reason)])
		}

		return wrap(to: to, stanzaID: stanzaID, action: BinaryNode(tag: "terminate", attrs: attrs))
	}

	/// `<transport>`: the caller answers a callee's `<accept>` with it.
	public static func transport(
		callID: String,
		to: String,
		callCreator: String,
		stanzaID: String
	) -> BinaryNode {
		wrap(to: to, stanzaID: stanzaID, action: BinaryNode(
			tag: "transport",
			attrs: [
				"call-id": callID,
				"call-creator": callCreator,
				"p2p-cand-round": "1",
				"transport-message-type": "1"
			],
			content: .nodes([BinaryNode(tag: "net", attrs: ["medium": "2", "protocol": "0"])])
		))
	}

	/// `<relaylatency>`: announces the relay the caller dials. Latency is encoded as `0x2000000 + ms`.
	public static func relayLatency(
		callID: String,
		to: String,
		callCreator: String,
		stanzaID: String,
		latencyMs: Int,
		relayName: String,
		relayAddress: Data,
		devices: [String]
	) -> BinaryNode {
		var children = [BinaryNode(
			tag: "te",
			attrs: ["latency": String(0x0200_0000 + latencyMs), "relay_name": relayName],
			content: .data(relayAddress)
		)]
		if !devices.isEmpty {
			children.append(BinaryNode(
				tag: "destination",
				content: .nodes(devices.map { BinaryNode(tag: "to", attrs: ["jid": $0]) })
			))
		}

		return wrap(to: to, stanzaID: stanzaID, action: action("relaylatency", callID, callCreator, children))
	}

	/// `<receipt>` for an incoming `<offer>`; this is what makes the caller's phone show "ringing".
	public static func offerReceipt(
		callID: String,
		to: String,
		callCreator: String,
		stanzaID: String,
		from: String?
	) -> BinaryNode {
		BinaryNode(
			tag: "receipt",
			attrs: BinaryNodeAttributes.trimmingUndefined([("to", to), ("id", stanzaID), ("from", from)]),
			content: .nodes([BinaryNode(tag: "offer", attrs: ["call-id": callID, "call-creator": callCreator])])
		)
	}

	// MARK: Pieces

	private static var encoptNode: BinaryNode {
		BinaryNode(tag: "encopt", attrs: ["keygen": "2"])
	}

	private static func audioNode(_ rate: String) -> BinaryNode {
		BinaryNode(tag: "audio", attrs: ["enc": "opus", "rate": rate])
	}

	private static func capabilityNode(_ blob: Data) -> BinaryNode {
		BinaryNode(tag: "capability", attrs: ["ver": "1"], content: .data(blob))
	}

	private static func encNode(_ key: CallOfferDeviceKey) -> BinaryNode {
		BinaryNode(
			tag: "enc",
			attrs: ["v": "2", "type": key.encryptionType, "count": "0"],
			content: .data(key.ciphertext)
		)
	}

	private static func action(
		_ tag: String,
		_ callID: String,
		_ callCreator: String,
		_ children: [BinaryNode]
	) -> BinaryNode {
		BinaryNode(
			tag: tag,
			attrs: ["call-id": callID, "call-creator": callCreator],
			content: .nodes(children)
		)
	}

	private static func wrap(to: String, stanzaID: String, action: BinaryNode) -> BinaryNode {
		BinaryNode(tag: "call", attrs: ["to": to, "id": stanzaID], content: .nodes([action]))
	}
}
