import Foundation

/// Whether a call link starts a voice or a video call. The link's address says which.
public enum CallLinkMedia: String, Codable, Hashable, Sendable {
	case audio
	case video
}

/// A reusable link into a call.
public struct CallLink: Codable, Hashable, Sendable {
	private static let host = "call.whatsapp.com"

	public let token: String
	public let media: CallLinkMedia

	public init(token: String, media: CallLinkMedia) {
		self.token = token
		self.media = media
	}

	/// Reads a link as people share it, with or without its scheme. Nothing else on that host is a call.
	public init?(url text: String) {
		var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
		if value.hasPrefix(Self.host) {
			value = "https://\(value)"
		}
		guard let components = URLComponents(string: value),
			  components.scheme?.lowercased() == "https",
			  components.host?.lowercased() == Self.host else {
			return nil
		}

		let path = components.path.split(separator: "/", omittingEmptySubsequences: true)
		guard path.count == 2, let media = CallLinkMedia(rawValue: String(path[0])) else {
			return nil
		}

		self.init(token: String(path[1]), media: media)
	}

	public var url: String {
		"https://\(Self.host)/\(media.rawValue)/\(token)"
	}
}

/// What a link says about itself, without joining it.
public struct CallLinkPreview: Equatable, Sendable {
	public let link: CallLink
	public let creator: String
	public let creatorPhone: String?
	public let isApprovalRequired: Bool
	/// This account decides who comes in.
	public let isAdmin: Bool

	public init(link: CallLink, creator: String, creatorPhone: String?, isApprovalRequired: Bool, isAdmin: Bool) {
		self.link = link
		self.creator = creator
		self.creatorPhone = creatorPhone
		self.isApprovalRequired = isApprovalRequired
		self.isAdmin = isAdmin
	}
}

/// Someone asking to come in.
public struct CallWaitingRoomUser: Equatable, Sendable {
	public let jid: String
	public let phoneJID: String?
	public let state: String

	public init(jid: String, phoneJID: String? = nil, state: String) {
		self.jid = jid
		self.phoneJID = phoneJID
		self.state = state
	}
}

/// Who is waiting to get into a link's call. Each one replaces the last whole.
public struct CallWaitingRoom: Equatable, Sendable {
	/// More than this in one stanza is not a room anyone can be shown.
	static let maxUsers = 128

	public let callID: String
	public let callCreator: String
	public let link: CallLink
	public var isEnabled: Bool
	public let isAdmin: Bool
	public let transactionID: UInt32?
	public let users: [CallWaitingRoomUser]

	public init(
		callID: String,
		callCreator: String,
		link: CallLink,
		isEnabled: Bool,
		isAdmin: Bool,
		transactionID: UInt32? = nil,
		users: [CallWaitingRoomUser] = []
	) {
		self.callID = callID
		self.callCreator = callCreator
		self.link = link
		self.isEnabled = isEnabled
		self.isAdmin = isAdmin
		self.transactionID = transactionID
		self.users = users
	}
}

/// Where joining a link left this device: in the call, or waiting for someone to let it in.
public struct CallLinkJoin: Equatable, Sendable {
	public let link: CallLink
	public let callID: String
	public let callCreator: String
	public var isInWaitingRoom: Bool
	public var waitingRoom: CallWaitingRoom?
	public var group: GroupCallUpdate?

	public init(
		link: CallLink,
		callID: String,
		callCreator: String,
		isInWaitingRoom: Bool,
		waitingRoom: CallWaitingRoom?,
		group: GroupCallUpdate?
	) {
		self.link = link
		self.callID = callID
		self.callCreator = callCreator
		self.isInWaitingRoom = isInWaitingRoom
		self.waitingRoom = waitingRoom
		self.group = group
	}
}

/// What a `<screen_share>` announces.
public enum CallScreenShareState: Int, Equatable, Sendable {
	case started = 1
	case stopped = 2
}

// MARK: Parsing

extension CallLink {
	/// The link in the ack of a `<link_create>`.
	public static func parse(createAck node: BinaryNode) throws -> CallLink {
		try CallLinkStanza.validate(node)
		guard let child = node.firstChild(named: "link_create") else {
			throw GroupCallStanzaError.malformed("the link_create ack has no link")
		}

		return try CallLink(
			token: CallLinkStanza.required(child.attrs["token"], "token"),
			media: CallLinkStanza.media(child.attrs["media"])
		)
	}
}

extension CallLinkPreview {
	/// What the ack of a `<link_query>` says.
	public static func parse(queryAck node: BinaryNode) throws -> CallLinkPreview {
		try CallLinkStanza.validate(node)
		guard let child = node.firstChild(named: "link_query") else {
			throw GroupCallStanzaError.malformed("the link_query ack has no link")
		}

		let waiting = child.firstChild(named: "waiting_room")
		return try CallLinkPreview(
			link: CallLink(
				token: CallLinkStanza.required(child.attrs["token"], "token"),
				media: CallLinkStanza.media(child.attrs["media"])
			),
			creator: CallLinkStanza.required(child.attrs["link_creator"], "link_creator"),
			creatorPhone: child.attrs["link_creator_pn"],
			isApprovalRequired: waiting?.attrs["enabled"] == "1",
			isAdmin: waiting?.attrs["is_admin"] == "1"
		)
	}
}

extension CallWaitingRoom {
	/// An authoritative `<waiting_room_update>`.
	public static func parse(update node: BinaryNode) throws -> CallWaitingRoom {
		guard let child = node.firstChild(named: "waiting_room") else {
			throw GroupCallStanzaError.malformed("waiting_room_update is missing waiting_room")
		}

		let room = try parse(room: child)
		guard room.callID == node.attrs["call-id"], room.callCreator == node.attrs["call-creator"] else {
			throw GroupCallStanzaError.malformed("waiting_room_update names another call")
		}

		return room
	}

	static func parse(room node: BinaryNode) throws -> CallWaitingRoom {
		let users = node.children(named: "user")
		guard users.count <= maxUsers else {
			throw GroupCallStanzaError.malformed("too many people in the waiting room")
		}

		return try CallWaitingRoom(
			callID: CallLinkStanza.required(node.attrs["call-id"], "call-id"),
			callCreator: CallLinkStanza.required(node.attrs["call-creator"], "call-creator"),
			link: CallLink(
				token: CallLinkStanza.required(node.attrs["link-token"], "link-token"),
				media: CallLinkStanza.media(node.attrs["media"])
			),
			isEnabled: node.attrs["enabled"] == "1",
			isAdmin: node.attrs["is_admin"] == "1",
			transactionID: node.attrs["transaction-id"].flatMap(UInt32.init),
			users: users.map { user in
				try CallWaitingRoomUser(
					jid: CallLinkStanza.required(user.attrs["jid"], "user jid"),
					phoneJID: user.attrs["user_pn"],
					state: CallLinkStanza.required(user.attrs["state"], "user state")
				)
			}
		)
	}
}

extension CallLinkJoin {
	/// The ack of a `<link_join>`, which either lets this device in or puts it in the waiting room.
	public static func parse(ack node: BinaryNode, link: CallLink) throws -> CallLinkJoin {
		try CallLinkStanza.validate(node)
		let room = try node.firstChild(named: "waiting_room").map(CallWaitingRoom.parse(room:))
		let group = try GroupCallUpdate.parse(offerAck: node)
		if let room, room.link != link {
			throw GroupCallStanzaError.malformed("the waiting room is for another link")
		}
		if let room, let group {
			guard room.callID == group.callID, room.callCreator == group.callCreator else {
				throw GroupCallStanzaError.malformed("the waiting room and the roster name different calls")
			}
			guard room.link.media.rawValue == group.media else {
				throw GroupCallStanzaError.malformed("the waiting room and the roster disagree on the media")
			}
		}
		if group == nil, room?.isEnabled != true {
			throw GroupCallStanzaError.malformed("the link_join ack lets nobody in and has nowhere to wait")
		}
		if let group, group.media != link.media.rawValue {
			throw GroupCallStanzaError.malformed("the link_join ack changed the media")
		}
		guard let callID = room?.callID ?? group?.callID, let creator = room?.callCreator ?? group?.callCreator else {
			throw GroupCallStanzaError.malformed("the link_join ack names no call")
		}

		return CallLinkJoin(
			link: link,
			callID: callID,
			callCreator: creator,
			isInWaitingRoom: group == nil,
			waitingRoom: room,
			group: group
		)
	}
}

enum CallLinkStanza {
	/// A refused action says so in the ack's `error`. `207` is for rosters, which these are not.
	static func validate(_ node: BinaryNode) throws {
		if let error = node.attrs["error"], !error.isEmpty, error != "0" {
			throw GroupCallStanzaError.rejected(error)
		}
	}

	static func required(_ value: String?, _ name: String) throws -> String {
		guard let value, !value.isEmpty else {
			throw GroupCallStanzaError.malformed("missing \(name)")
		}

		return value
	}

	static func media(_ value: String?) throws -> CallLinkMedia {
		guard let media = value.flatMap(CallLinkMedia.init(rawValue:)) else {
			throw GroupCallStanzaError.malformed("unsupported link media")
		}

		return media
	}
}
