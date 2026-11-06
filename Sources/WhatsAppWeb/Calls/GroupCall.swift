import Foundation

/// How many endpoints a group call holds, from WhatsApp's `group_call_max_participants`.
public enum GroupCallLimits {
	public static let maxParticipants = 32
	/// The local endpoint takes one of the slots.
	public static let maxRemoteParticipants = maxParticipants - 1
}

/// Where a group call's signaling goes: the call service fans it out to the roster.
public func groupCallScope(callID: String) -> String {
	"\(callID)@call"
}

/// Pieces of a JID that call code compares. Device ids and namespaces matter: the same user text in
/// `@lid` and `@s.whatsapp.net` names different identities, and media keys derive from the exact form.
enum CallJID {
	static func user(_ jid: String) -> String {
		JID(jid).map { "\($0.user)@\($0.server)" } ?? jid
	}

	static func device(_ jid: String) -> Int {
		JID(jid)?.device ?? 0
	}

	static func isSameUser(_ lhs: String, _ rhs: String) -> Bool {
		user(lhs) == user(rhs)
	}

	static func isHosted(_ jid: String) -> Bool {
		jid.isHostedUserJID || jid.isHostedLIDUserJID || device(jid) == 99
	}
}

/// One device in a group call's roster.
public struct GroupCallDevice: Equatable, Sendable {
	public var jid: String
	public var platform: String?
	/// The relay's id for this device's media session. Zero is real: the creator gets it.
	public var pid: UInt32?
	public var capabilityVersion: UInt32?
	public var capability: Data

	public init(
		jid: String,
		platform: String? = nil,
		pid: UInt32? = nil,
		capabilityVersion: UInt32? = nil,
		capability: Data = Data()
	) {
		self.jid = jid
		self.platform = platform
		self.pid = pid
		self.capabilityVersion = capabilityVersion
		self.capability = capability
	}
}

/// One user in a group call's roster.
public struct GroupCallParticipant: Equatable, Sendable {
	public var jid: String
	/// The phone-number alias of a LID participant, when the roster gives one.
	public var phoneJID: String?
	public var state: String?
	public var type: String?
	/// The service's code for this entry. Separate from the ack's own status: a `207` ack serves the
	/// call while individual participants fail.
	public var error: Int?
	public var devices: [GroupCallDevice]

	public init(
		jid: String,
		phoneJID: String? = nil,
		state: String? = nil,
		type: String? = nil,
		error: Int? = nil,
		devices: [GroupCallDevice] = []
	) {
		self.jid = jid
		self.phoneJID = phoneJID
		self.state = state
		self.type = type
		self.error = error
		self.devices = devices
	}

	public var isConnected: Bool {
		state == "connected"
	}
}

/// One transaction-ordered snapshot of a group call. The server owns the roster: an accepted snapshot
/// replaces the last one whole, and is never merged into it.
public struct GroupCallUpdate: Equatable, Sendable {
	public var callID: String
	public var callCreator: String
	public var groupJID: String?
	/// Zero only on an initial offer's ack, before the service has ordered anything.
	public var transactionID: UInt32
	/// `audio` or `video`.
	public var media: String
	public var connectedLimit: UInt32
	public var isJoinable: Bool
	public var isAVUpgradable: Bool
	/// This device has to generate and distribute the next media key.
	public var isRekeyRequested: Bool
	public var participants: [GroupCallParticipant]
	public var relay: CallRelayData?

	public init(
		callID: String,
		callCreator: String,
		groupJID: String? = nil,
		transactionID: UInt32,
		media: String,
		connectedLimit: UInt32 = UInt32(GroupCallLimits.maxParticipants),
		isJoinable: Bool = true,
		isAVUpgradable: Bool = false,
		isRekeyRequested: Bool = false,
		participants: [GroupCallParticipant],
		relay: CallRelayData? = nil
	) {
		self.callID = callID
		self.callCreator = callCreator
		self.groupJID = groupJID
		self.transactionID = transactionID
		self.media = media
		self.connectedLimit = connectedLimit
		self.isJoinable = isJoinable
		self.isAVUpgradable = isAVUpgradable
		self.isRekeyRequested = isRekeyRequested
		self.participants = participants
		self.relay = relay
	}

	public var isVideo: Bool {
		media == "video"
	}

	/// The entry for `localDevice`, which may appear under its LID or its phone-number alias.
	public func localDevice(matching localDevice: String) -> GroupCallDevice? {
		for participant in participants where participant.isConnected {
			if let device = participant.devices.first(where: { Self.isLocal($0, in: participant, localDevice: localDevice) }) {
				return device
			}
		}

		return nil
	}

	/// Connected remote devices holding a media session: the ones this device exchanges media with.
	func activeRemoteDevices(localDevice: String) -> [(participant: GroupCallParticipant, device: GroupCallDevice)] {
		participants.filter(\.isConnected).flatMap { participant in
			participant.devices
				.filter { $0.pid != nil && !Self.isLocal($0, in: participant, localDevice: localDevice) }
				.map { (participant, $0) }
		}
	}

	/// Matches on the user (its LID or alias) and the device id together: the same device id on another
	/// account is another device, and a sibling device of this account is a real remote.
	static func isLocal(_ device: GroupCallDevice, in participant: GroupCallParticipant, localDevice: String) -> Bool {
		let ownsUser = CallJID.isSameUser(participant.jid, localDevice)
			|| participant.phoneJID.map { CallJID.isSameUser($0, localDevice) } == true
		guard ownsUser, CallJID.device(device.jid) == CallJID.device(localDevice) else {
			return false
		}

		return CallJID.isSameUser(device.jid, participant.jid)
			|| participant.phoneJID.map { CallJID.isSameUser(device.jid, $0) } == true
	}
}

/// One shared media key, delivered directly to each participant device.
public struct GroupCallEpoch: Equatable, Sendable {
	public let transactionID: UInt32
	public let key: Data

	public init(transactionID: UInt32, key: Data) {
		self.transactionID = transactionID
		self.key = key
	}
}

public enum GroupCallStanzaError: Error, Equatable, Sendable {
	case malformed(String)
	/// The service refused the action, with this code.
	case rejected(String)
}

// MARK: Parsing

extension GroupCallUpdate {
	/// The snapshot inside an `<offer>`, when it has one. A call without `<group_info>` is a 1:1 call.
	public static func parse(offer: BinaryNode) throws -> GroupCallUpdate? {
		guard let info = offer.firstChild(named: "group_info") else {
			return nil
		}

		let callID = try required(offer.attrs["call-id"], "call-id")
		let creator = try required(offer.attrs["call-creator"], "call-creator")
		var update = try parseInfo(info, callID: callID, creator: creator, isPartial: false)
		if let groupJID = offer.attrs["group-jid"] {
			if let nested = update.groupJID, nested != groupJID {
				throw GroupCallStanzaError.malformed("group_info group-jid does not match the offer")
			}
			update.groupJID = groupJID
		}
		if let nested = info.attrs["call-id"], nested != callID {
			throw GroupCallStanzaError.malformed("group_info call-id does not match the offer")
		}
		if let nested = info.attrs["call-creator"], nested != creator {
			throw GroupCallStanzaError.malformed("group_info call-creator does not match the offer")
		}
		if let joinable = offer.attrs["joinable"] {
			update.isJoinable = joinable == "1"
		}

		return update
	}

	/// An authoritative `<group_update>`.
	public static func parse(groupUpdate node: BinaryNode) throws -> GroupCallUpdate {
		guard let info = node.firstChild(named: "group_info") else {
			throw GroupCallStanzaError.malformed("group_update is missing group_info")
		}

		var update = try parseInfo(
			info,
			callID: required(node.attrs["call-id"], "call-id"),
			creator: required(node.attrs["call-creator"], "call-creator"),
			isPartial: false
		)
		update.isAVUpgradable = node.firstChild(named: "av_upgrade")?.attrs["av-upgradable"] == "1"
		update.relay = node.firstChild(named: "relay").flatMap(CallRelayData.parse(relay:))
		return update
	}

	/// The snapshot in the ack of an initial offer. Its `error` is a status, not a refusal by itself:
	/// `0` serves the action and `207` serves it while individual participants fail, and both carry the
	/// roster. Any other code stops the call there.
	public static func parse(offerAck node: BinaryNode) throws -> GroupCallUpdate? {
		if let error = node.attrs["error"], !error.isEmpty, error != "0", error != "207" {
			throw GroupCallStanzaError.rejected(error)
		}
		guard let info = node.firstChild(named: "group_info") else {
			return nil
		}

		// The roster the service accepted, ahead of the update plane: an ack can omit the ordering
		// transaction and the limit, and zero is the state a freshly acked offer really is in.
		var update = try parseInfo(
			info,
			callID: required(info.attrs["call-id"], "call-id"),
			creator: required(info.attrs["call-creator"], "call-creator"),
			isPartial: true
		)
		update.relay = node.firstChild(named: "relay").flatMap(CallRelayData.parse(relay:))
		return update
	}

	/// The roster in the ack of a `<lobby>`, which need not name the call again. `nil` when it has none.
	public static func parse(lobbyAck node: BinaryNode, callID: String, callCreator: String) throws -> GroupCallUpdate? {
		guard let info = node.firstChild(named: "group_info") else {
			return nil
		}

		return try parseInfo(
			info,
			callID: info.attrs["call-id"] ?? callID,
			creator: info.attrs["call-creator"] ?? callCreator,
			isPartial: true
		)
	}

	private static func parseInfo(
		_ node: BinaryNode,
		callID: String,
		creator: String,
		isPartial: Bool
	) throws -> GroupCallUpdate {
		let transactionID: UInt32
		let connectedLimit: UInt32
		if isPartial {
			transactionID = try optionalUInt32(node.attrs["transaction-id"]) ?? 0
			connectedLimit = try optionalUInt32(node.attrs["connected-limit"]) ?? 0
		} else {
			transactionID = try requiredUInt32(node.attrs["transaction-id"], "transaction-id")
			connectedLimit = try requiredUInt32(node.attrs["connected-limit"], "connected-limit")
		}

		return try GroupCallUpdate(
			callID: callID,
			callCreator: creator,
			groupJID: node.attrs["group-jid"],
			transactionID: transactionID,
			media: required(node.attrs["media"], "media"),
			connectedLimit: connectedLimit,
			isJoinable: node.attrs["joinable"] == "1",
			isRekeyRequested: node.attrs["rekey"] == "1",
			participants: node.children(named: "user").map(parseParticipant)
		)
	}

	private static func parseParticipant(_ node: BinaryNode) throws -> GroupCallParticipant {
		try GroupCallParticipant(
			jid: required(node.attrs["jid"], "user jid"),
			phoneJID: node.attrs["user_pn"],
			state: node.attrs["state"].flatMap { $0.isEmpty ? nil : $0 },
			type: node.attrs["type"],
			error: node.attrs["error"].flatMap(Int.init),
			devices: node.children(named: "device").map(parseDevice)
		)
	}

	private static func parseDevice(_ node: BinaryNode) throws -> GroupCallDevice {
		let capability = node.firstChild(named: "capability")
		return try GroupCallDevice(
			jid: required(node.attrs["jid"], "device jid"),
			platform: node.attrs["platform"],
			pid: optionalUInt32(node.attrs["pid"]),
			capabilityVersion: capability?.attrs["ver"].flatMap(UInt32.init),
			capability: capability.flatMap(CallRelayData.contentBytes) ?? Data()
		)
	}

	private static func required(_ value: String?, _ name: String) throws -> String {
		guard let value, !value.isEmpty else {
			throw GroupCallStanzaError.malformed("missing \(name)")
		}

		return value
	}

	private static func requiredUInt32(_ value: String?, _ name: String) throws -> UInt32 {
		guard let parsed = try optionalUInt32(value) else {
			throw GroupCallStanzaError.malformed("missing \(name)")
		}

		return parsed
	}

	private static func optionalUInt32(_ value: String?) throws -> UInt32? {
		guard let value else {
			return nil
		}
		guard let parsed = UInt32(value) else {
			throw GroupCallStanzaError.malformed("invalid integer \(value)")
		}

		return parsed
	}
}

// MARK: State

/// Membership of one group call. Updates are transaction ordered and replace the roster whole. An
/// omitted relay means no new allocation, and an omitted PID means an unchanged one, so both carry over
/// from the last snapshot.
public struct GroupCallState: Sendable {
	public enum Apply: Equatable, Sendable {
		/// A newer roster was committed.
		case applied
		/// The roster stands and a newer relay allocation was taken from an older snapshot.
		case relayOnly
		case stale
		case identityMismatch
		case invalid
	}

	public let callID: String
	public let callCreator: String
	public private(set) var snapshot: GroupCallUpdate?
	/// A rekey the initial ack asked for, which transaction zero could not name. The first ordered roster
	/// answers it, whether or not that update repeats the flag.
	private var owedRekey = false

	public init(callID: String, callCreator: String) {
		self.callID = callID
		self.callCreator = callCreator
	}

	public mutating func apply(_ update: GroupCallUpdate) -> Apply {
		apply(update, isInitialAck: false)
	}

	/// Admits the snapshot of an initial offer's ack. Only the first snapshot may be partial: once a
	/// roster has been ordered, a partial one is the ack being overtaken.
	public mutating func applyInitialOfferAck(_ update: GroupCallUpdate) -> Apply {
		apply(update, isInitialAck: true)
	}

	/// Keeps the relay of an ack whose roster was overtaken, when what overtook it brought none. A later
	/// allocation still replaces it, and the roster stands.
	public mutating func adoptRelayIfMissing(_ relay: CallRelayData?) {
		if snapshot?.relay == nil {
			snapshot?.relay = relay
		}
	}

	/// Lets go of the relay allocation. One given to this device before it left means nothing for its
	/// return, and the next can carry the same number, so it would not read as newer.
	public mutating func dropRelay() {
		snapshot?.relay = nil
	}

	/// Takes the rekey the initial ack left outstanding. Consumed exactly once.
	public mutating func takeOwedRekey() -> Bool {
		defer { owedRekey = false }
		return owedRekey
	}

	private mutating func apply(_ incoming: GroupCallUpdate, isInitialAck: Bool) -> Apply {
		var update = incoming
		guard update.callID == callID, update.callCreator == callCreator else {
			return .identityMismatch
		}
		// A conflict is refused before anything else decides: an overtaken ack from another group is not
		// merely late, and the offer path would keep it beside the roster it holds.
		if let current = snapshot?.groupJID {
			if let stated = update.groupJID, stated != current {
				return .identityMismatch
			}
			update.groupJID = current
		}

		var isPartial = false
		if isInitialAck {
			if snapshot == nil {
				isPartial = true
			} else if update.transactionID == 0 || update.connectedLimit == 0 {
				return .stale
			}
		}
		guard Self.isValid(update, isPartial: isPartial) else {
			return .invalid
		}

		let advancesRelay = update.relay.map { incomingRelay in
			guard let held = snapshot?.relay else {
				return true
			}
			guard let next = incomingRelay.transactionID else {
				return false
			}

			return held.transactionID.map { next > $0 } ?? true
		} ?? false

		if var current = snapshot, update.transactionID <= current.transactionID {
			// An older roster may supply a newer allocation, but not replace the roster.
			guard advancesRelay else {
				return .stale
			}

			current.relay = update.relay
			snapshot = current
			return .relayOnly
		}

		if let previous = snapshot {
			Self.inheritPIDs(from: previous, into: &update)
		}
		if !advancesRelay {
			// Roster progress cannot revoke or roll back a held allocation.
			update.relay = snapshot?.relay
		}
		guard Self.isValid(update, isPartial: isPartial) else {
			return .invalid
		}

		if isPartial, update.isRekeyRequested, update.transactionID == 0 {
			owedRekey = true
		}
		snapshot = update
		return .applied
	}

	/// Roster-only updates leave out PIDs that did not change. Exact namespace matches win, and a mapped
	/// PN/LID alias only fills what is left, keeping the stored JID: key derivations differ by namespace.
	private static func inheritPIDs(from previous: GroupCallUpdate, into update: inout GroupCallUpdate) {
		var known = [String: UInt32]()
		for participant in previous.participants {
			for device in participant.devices {
				if let pid = device.pid {
					known[device.jid] = pid
				}
			}
		}
		for participant in previous.participants {
			for device in participant.devices {
				if let pid = device.pid, let alias = mappedDevice(in: participant, device: device.jid), known[alias] == nil {
					known[alias] = pid
				}
			}
		}

		for participantIndex in update.participants.indices where update.participants[participantIndex].isConnected {
			let participant = update.participants[participantIndex]
			for deviceIndex in participant.devices.indices where participant.devices[deviceIndex].pid == nil {
				let jid = participant.devices[deviceIndex].jid
				update.participants[participantIndex].devices[deviceIndex].pid = known[jid]
					?? mappedDevice(in: participant, device: jid).flatMap { known[$0] }
			}
		}
	}

	private static func mappedDevice(in participant: GroupCallParticipant, device: String) -> String? {
		guard let phone = participant.phoneJID,
			  let owner = JID(participant.jid), owner.server == JIDServer.lid.rawValue,
			  let alias = JID(phone), alias.server == JIDServer.user.rawValue,
			  let parsed = JID(device) else {
			return nil
		}

		let other: JID
		if CallJID.isSameUser(device, participant.jid) {
			other = alias
		} else if CallJID.isSameUser(device, phone) {
			other = owner
		} else {
			return nil
		}

		return parsed.device.map { "\(other.user):\($0)@\(other.server)" } ?? "\(other.user)@\(other.server)"
	}

	static func isValid(_ update: GroupCallUpdate, isPartial: Bool) -> Bool {
		let connected = update.participants.filter(\.isConnected)
		let activeDevices = connected.flatMap(\.devices).filter { $0.pid != nil }.count
		if !isPartial, update.transactionID == 0 || update.connectedLimit == 0 {
			return false
		}
		guard update.connectedLimit <= GroupCallLimits.maxParticipants,
			  update.participants.count <= GroupCallLimits.maxParticipants,
			  activeDevices <= GroupCallLimits.maxParticipants,
			  update.connectedLimit == 0 || connected.count <= update.connectedLimit,
			  update.media == "audio" || update.media == "video" else {
			return false
		}

		var users = Set<String>()
		var pids = Set<UInt32>()
		var devices = Set<String>()
		for participant in update.participants {
			guard users.insert(CallJID.user(participant.jid)).inserted else {
				return false
			}
			if let phone = participant.phoneJID, !users.insert(CallJID.user(phone)).inserted {
				return false
			}
			for device in participant.devices {
				let belongs = CallJID.isSameUser(device.jid, participant.jid)
					|| participant.phoneJID.map { CallJID.isSameUser(device.jid, $0) } == true
				guard belongs, devices.insert(device.jid).inserted else {
					return false
				}
				if let pid = device.pid, !pids.insert(pid).inserted {
					return false
				}
			}
		}

		return hasCollisionFreeRoutes(update)
	}

	/// Media is routed by SSRC before it is authenticated, so a duplicate would let one participant's
	/// packets land in another's decoder.
	private static func hasCollisionFreeRoutes(_ update: GroupCallUpdate) -> Bool {
		var participantIDs = Set<String>()
		var audio = Set<UInt32>()
		var video = Set<UInt32>()
		var slots = Set<UInt32>()
		for device in update.participants.filter(\.isConnected).flatMap(\.devices) where device.pid != nil {
			let id = CallMediaCrypto.formatParticipantID(device.jid)
			guard participantIDs.insert(id).inserted,
				  audio.insert(CallRelayAllocate.audioSSRC(callID: update.callID, participantID: id)).inserted,
				  video.insert(CallRelayAllocate.videoSSRC(callID: update.callID, participantID: id)).inserted else {
				return false
			}
			for slot in UInt32(0)..<UInt32(CallRelayAllocate.streamSlots.count)
			where !slots.insert(CallRelayAllocate.ssrc(callID: update.callID, participantID: id, slot: slot)).inserted {
				return false
			}
		}

		return true
	}
}

// MARK: Relay

extension CallRelayData {
	/// This allocation without the endpoints a group call cannot use. A group's relay has no fallback
	/// path through an FNA address, so one is only useful when nothing else exists.
	var forGroupMedia: CallRelayData {
		var relay = self
		let usable = endpoints.filter { endpoint in
			!endpoint.isFNA && endpoint.primaryIPv4.map { $0.port != 0 } == true
				&& relayTokens.indices.contains(endpoint.tokenID) && !relayTokens[endpoint.tokenID].isEmpty
		}
		if !usable.isEmpty {
			relay.endpoints = usable
		}

		return relay
	}
}

/// A group relay wraps forwarded media in a small header.
enum CallRelayForwarding {
	/// `0x09` marks the envelope, and the next byte sets its size. A packet using a form this client does
	/// not know is dropped rather than passed on, so its metadata never reaches the media parsers.
	static func unwrap(_ data: Data) -> Data? {
		guard data.first == 0x09 else {
			return data
		}
		guard data.count >= 2 else {
			return nil
		}

		let headerLength: Int
		switch data[data.startIndex + 1] {
		case 2: headerLength = 8
		case 4: headerLength = 12
		case 7: headerLength = 18
		default: return nil
		}

		let payload = data.dropFirst(headerLength)
		guard payload.count >= CallRTPHeader.fixedLength, let first = payload.first, first >> 6 == 2 else {
			return nil
		}

		return Data(payload)
	}
}
