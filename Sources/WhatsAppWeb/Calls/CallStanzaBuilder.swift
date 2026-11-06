import Foundation

/// Capability blobs advertised in call stanzas. Bit 31 of the mask is `use_mlow_codec_v1`; the
/// "standard Opus" variants clear it so the peer sends plain Opus instead of the proprietary MLow.
public enum CallCapability {
	public static let offer = Data([0x01, 0x05, 0xf7, 0x09, 0xe0, 0xbb, 0x13])
	public static let preaccept = Data([0x01, 0x05, 0xf7, 0x09, 0xe0, 0xbb, 0x07])
	/// What a video `<offer>` carries. A video callee's `<preaccept>` uses `offer` instead.
	public static let videoOffer = Data([0x01, 0x05, 0xf7, 0x09, 0xe0, 0xbb, 0x53])
	public static let standardOpusOffer = clearingMLow(offer)
	public static let standardOpusPreaccept = clearingMLow(preaccept)
	public static let standardOpusVideoOffer = clearingMLow(videoOffer)

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

/// `state` of a mid-call `<video>` stanza.
public enum CallVideoState: Int, Equatable, Sendable {
	case disabled = 0
	case enabled = 1
	case paused = 2
	case upgradeRequest = 3
	case upgradeAccept = 4
	case upgradeReject = 5
	case stopped = 6
	case upgradeRejectByTimeout = 7
	case upgradeCancel = 8
	case upgradeCancelByTimeout = 9
	case unknownPeer = 10
	case upgradeRequestV2 = 11
	case error = 20
}

/// Peer experiment metadata a video `<accept>` mirrors from the offer.
public struct CallPeerMetadata: Equatable, Sendable {
	public let abTestBucket: String?
	public let abTestBucketIDList: String?

	public init(abTestBucket: String?, abTestBucketIDList: String?) {
		self.abTestBucket = abTestBucket
		self.abTestBucketIDList = abTestBucketIDList
	}

	init?(offer: BinaryNode) {
		guard let metadata = offer.firstChild(named: "metadata") else {
			return nil
		}

		self.init(
			abTestBucket: metadata.attrs["peer_abtest_bucket"],
			abTestBucketIDList: metadata.attrs["peer_abtest_bucket_id_list"]
		)
	}
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

/// Builders for the `<call>` stanzas of a 1:1 call. Child order matters: the server rejects
/// out-of-order children, so each builder follows the order the official client sends.
public enum CallStanzaBuilder {
	/// One `<audio>` per offered rate. WhatsApp selects its audio path by this rate, and the 16 kHz
	/// Opus this library sends and receives is signaled as 16000 alone.
	public static let defaultAudioRates = ["16000"]
	public static let rejectReasonBusy = "busy"
	public static let terminateReasonAcceptedElsewhere = "accepted_elsewhere"
	/// The decoder capabilities this client advertises. Only H.264: a callee that took a wider list at
	/// its word could send something this client cannot decode.
	public static let videoDecoders = "H264"
	/// The encoder name WhatsApp's `<video>` reader accepts, spelled differently from `videoDecoders`
	/// on purpose: an offer naming `h264` is delivered, acknowledged and never rings.
	public static let videoEncoder = "h.264"
	/// A rotation of zero: this client's camera is upright, and no call has rotated it yet.
	public static let uprightOrientation = "0"

	/// `<offer>`: privacy → audio… → [video] → net → capability → destination|enc → encopt →
	/// device-identity.
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
		audioRates: [String] = defaultAudioRates,
		video: Bool = false
	) -> BinaryNode {
		var children = [BinaryNode]()
		if let privacyToken {
			children.append(BinaryNode(tag: "privacy", content: .data(privacyToken)))
		}
		children += audioRates.map(audioNode)
		if video {
			// A 1:1 offer carries no geometry: `1920x1080` is the group shape, and a callee given it
			// answers without ever rendering the stream.
			children.append(BinaryNode(tag: "video", attrs: BinaryNodeAttributes([
				("enc", videoEncoder),
				("dec", videoDecoders),
				("screen_width", "0"),
				("screen_height", "0"),
				("device_orientation", uprightOrientation)
			])))
		}
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

	/// `<preaccept>`: audio… → [video] → encopt → capability. Sent by the callee while the user decides.
	public static func preaccept(
		callID: String,
		to: String,
		callCreator: String,
		stanzaID: String,
		capability: Data? = nil,
		audioRates: [String] = defaultAudioRates,
		video: Bool = false
	) -> BinaryNode {
		var children = audioRates.map(audioNode)
		if video {
			children.append(BinaryNode(tag: "video", attrs: BinaryNodeAttributes([
				("dec", videoDecoders),
				("device_orientation", uprightOrientation),
				("screen_width", "0"),
				("screen_height", "0")
			])))
		}
		let blob = capability ?? (video ? CallCapability.standardOpusOffer : CallCapability.standardOpusPreaccept)
		children += [encoptNode, capabilityNode(blob)]
		return wrap(to: to, stanzaID: stanzaID, action: action("preaccept", callID, callCreator, children))
	}

	/// `<accept>`: audio… → [video] → [te] → net → encopt → [metadata] → [capability] → [rte] →
	/// voip_settings. An official video accept has no capability child, and mirrors the offer's
	/// experiment metadata.
	public static func accept(
		callID: String,
		to: String,
		callCreator: String,
		stanzaID: String,
		relayTransportEndpoint: Data? = nil,
		routingToken: Data? = nil,
		voipSettings: Data? = CallVoIPSettings.standardOpus16kHzClock,
		capability: Data? = CallCapability.standardOpusOffer,
		audioRates: [String] = defaultAudioRates,
		video: Bool = false,
		peerMetadata: CallPeerMetadata? = nil
	) -> BinaryNode {
		var children = audioRates.map(audioNode)
		if video {
			children.append(BinaryNode(tag: "video", attrs: BinaryNodeAttributes([
				("dec", videoDecoders),
				("device_orientation", uprightOrientation)
			])))
		}
		if let relayTransportEndpoint {
			children.append(BinaryNode(tag: "te", attrs: ["priority": "2"], content: .data(relayTransportEndpoint)))
		}
		children.append(BinaryNode(tag: "net", attrs: ["medium": "2"]))
		children.append(encoptNode)
		if let peerMetadata, peerMetadata.abTestBucket != nil || peerMetadata.abTestBucketIDList != nil {
			children.append(BinaryNode(tag: "metadata", attrs: BinaryNodeAttributes.trimmingUndefined([
				("peer_abtest_bucket", peerMetadata.abTestBucket),
				("peer_abtest_bucket_id_list", peerMetadata.abTestBucketIDList)
			])))
		}
		if let capability, !video {
			children.append(capabilityNode(capability))
		}
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

	/// `<video>`: turns a direction of the call on or off, or negotiates upgrading a voice call.
	public static func videoState(
		callID: String,
		to: String,
		callCreator: String,
		stanzaID: String,
		state: CallVideoState,
		decoders: String? = nil,
		deviceOrientation: String? = nil,
		transactionID: UInt32? = nil
	) -> BinaryNode {
		wrap(to: to, stanzaID: stanzaID, action: BinaryNode(
			tag: "video",
			attrs: BinaryNodeAttributes.trimmingUndefined([
				("call-id", callID),
				("call-creator", callCreator),
				("state", String(state.rawValue)),
				("dec", decoders),
				("voip_settings", state == .upgradeRequestV2 ? "video" : nil),
				("device_orientation", deviceOrientation),
				("transaction-id", transactionID.map(String.init))
			])
		))
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
		devices: [String],
		transactionID: UInt32? = nil
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

		return wrap(to: to, stanzaID: stanzaID, action: BinaryNode(
			tag: "relaylatency",
			attrs: BinaryNodeAttributes.trimmingUndefined([
				("call-id", callID),
				("call-creator", callCreator),
				("transaction-id", transactionID.map(String.init))
			]),
			content: .nodes(children)
		))
	}

	// MARK: Group calls

	/// The initial `<offer>` of a group call, sent to the call scope: audio → [video] → net → group_info.
	/// It carries no key. The ack names who distributes the first one, by `enc_rekey`.
	public static func groupOffer(
		callID: String,
		callCreator: String,
		stanzaID: String,
		groupJID: String?,
		participants: [GroupCallParticipant],
		audioRate: String = "16000",
		video: Bool = false
	) -> BinaryNode {
		var children = [audioNode(audioRate)]
		if video {
			children.append(groupVideoNode)
		}
		children.append(BinaryNode(tag: "net", attrs: ["medium": "3"]))
		children.append(BinaryNode(tag: "group_info", content: .nodes(participants.map(groupUserNode))))

		return wrap(
			to: groupCallScope(callID: callID),
			stanzaID: stanzaID,
			action: BinaryNode(
				tag: "offer",
				attrs: BinaryNodeAttributes.trimmingUndefined([
					("call-id", callID),
					("call-creator", callCreator),
					("group-jid", groupJID)
				]),
				content: .nodes(children)
			)
		)
	}

	/// `<offer>` asking someone into a call already in progress, sent to them: audio → [video] → net →
	/// destination → group_info. On a 1:1 call it is also what makes it a group call. It names who is in
	/// the call, with their capabilities as they stated them. The key follows by `enc_rekey`.
	public static func groupInviteOffer(
		callID: String,
		to: String,
		callCreator: String,
		stanzaID: String,
		targetDevices: [String],
		participants: [GroupCallParticipant],
		audioRate: String = "16000",
		video: Bool = false
	) -> BinaryNode {
		var children = [audioNode(audioRate)]
		if video {
			children.append(groupVideoNode)
		}
		children.append(BinaryNode(tag: "net", attrs: ["medium": "2"]))
		children.append(BinaryNode(
			tag: "destination",
			content: .nodes(targetDevices.map { BinaryNode(tag: "to", attrs: ["jid": $0]) })
		))
		children.append(BinaryNode(tag: "group_info", content: .nodes(participants.map(groupUserNode))))
		return wrap(to: to, stanzaID: stanzaID, action: action("offer", callID, callCreator, children))
	}

	/// The group shape: its decoder names and geometry differ from a 1:1 offer's on purpose.
	private static var groupVideoNode: BinaryNode {
		BinaryNode(tag: "video", attrs: BinaryNodeAttributes([
			("enc", "h264"),
			("dec", "h264"),
			("orientation", "0"),
			("screen_width", "1920"),
			("screen_height", "1080"),
			("device_orientation", uprightOrientation)
		]))
	}

	/// `<enc_rekey>`: one shared media key, encrypted for one device.
	public static func groupEncRekey(
		callID: String,
		callCreator: String,
		stanzaID: String,
		transactionID: UInt32,
		deviceKey: CallOfferDeviceKey,
		deviceIdentity: Data? = nil
	) -> BinaryNode {
		var children = [encoptNode, encNode(deviceKey)]
		if let deviceIdentity {
			children.append(BinaryNode(tag: "device-identity", content: .data(deviceIdentity)))
		}

		return wrap(to: deviceKey.deviceJID, stanzaID: stanzaID, action: BinaryNode(
			tag: "enc_rekey",
			attrs: BinaryNodeAttributes([
				("call-id", callID),
				("call-creator", callCreator),
				("transaction-id", String(transactionID))
			]),
			content: .nodes(children)
		))
	}

	/// `<mute_v2>`: this side announcing its own microphone.
	public static func mute(
		callID: String,
		to: String,
		callCreator: String,
		stanzaID: String,
		muted: Bool
	) -> BinaryNode {
		wrap(to: to, stanzaID: stanzaID, action: BinaryNode(
			tag: "mute_v2",
			attrs: BinaryNodeAttributes([
				("call-id", callID),
				("call-creator", callCreator),
				("mute-state", muted ? "1" : "0")
			])
		))
	}

	private static func groupUserNode(_ participant: GroupCallParticipant) -> BinaryNode {
		BinaryNode(
			tag: "user",
			attrs: BinaryNodeAttributes.trimmingUndefined([("jid", participant.jid), ("state", participant.state)]),
			content: .nodes(participant.devices.map { device in
				guard !device.capability.isEmpty else {
					return BinaryNode(tag: "device", attrs: ["jid": device.jid])
				}

				return BinaryNode(tag: "device", attrs: ["jid": device.jid], content: .nodes([capabilityNode(device.capability)]))
			})
		)
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
