public enum DisconnectReasonCode {
	public static let connectionClosed = 428
	public static let connectionLost = 408
	public static let connectionReplaced = 440
	public static let timedOut = 408
	public static let loggedOut = 401
	public static let badSession = 500
	public static let restartRequired = 515
	public static let multideviceMismatch = 411
	public static let forbidden = 403
	public static let unavailableService = 503
	// Login failure reasons, as whatsmeow names them.
	public static let temporarilyBanned = 402
	public static let clientOutdated = 405
	public static let unknownLogout = 406
	public static let badUserAgent = 409
}

/// How the last connection ended: the reason the event carried, the server's status code, and
/// what that code means for reconnecting.
public struct WhatsAppDisconnect: Equatable, Sendable {
	public enum Kind: Equatable, Sendable {
		/// The phone or the server removed this device (401, 403, 406). The stored credentials no
		/// longer work, so only pairing again brings the account back.
		case loggedOut
		/// The account is temporarily banned (402).
		case banned
		/// Another connection with the same credentials took over (440).
		case replaced
		/// The server refuses this client as it is: outdated version (405), bad user agent (409) or a
		/// device list that does not match (411). The same login would fail again.
		case clientRejected
		/// The server asks for a new connection right away (515), as after pairing.
		case restartRequired
		/// Anything else: network loss, timeouts, server-side errors. Worth retrying later.
		case transient
	}

	public let reason: String
	public let statusCode: Int

	public init(reason: String, statusCode: Int) {
		self.reason = reason
		self.statusCode = statusCode
	}

	public var kind: Kind {
		switch statusCode {
		case DisconnectReasonCode.loggedOut, DisconnectReasonCode.forbidden, DisconnectReasonCode.unknownLogout:
			.loggedOut
		case DisconnectReasonCode.temporarilyBanned:
			.banned
		case DisconnectReasonCode.connectionReplaced:
			.replaced
		case DisconnectReasonCode.clientOutdated, DisconnectReasonCode.badUserAgent, DisconnectReasonCode.multideviceMismatch:
			.clientRejected
		case DisconnectReasonCode.restartRequired:
			.restartRequired
		default:
			.transient
		}
	}

	/// False when connecting again with the same credentials cannot succeed, or would take the
	/// session back from the connection that replaced it.
	public var allowsReconnect: Bool {
		switch kind {
		case .loggedOut, .banned, .replaced, .clientRejected: false
		case .restartRequired, .transient: true
		}
	}
}

public struct StreamErrorInfo: Equatable, Sendable {
	public let reason: String
	public let statusCode: Int

	public init(reason: String, statusCode: Int) {
		self.reason = reason
		self.statusCode = statusCode
	}
}

public enum ConnectionErrorMapper {
	public static func streamErrorInfo(from node: BinaryNode) -> StreamErrorInfo {
		let rawReason = firstChildTag(in: node) ?? "unknown"
		let statusCode = Int(node.attrs["code"] ?? "")
			?? mappedStatusCode(for: rawReason, type: firstChildType(in: node))
			?? DisconnectReasonCode.badSession
		let reason = statusCode == DisconnectReasonCode.restartRequired
			? "restart required"
			: rawReason

		return StreamErrorInfo(reason: reason, statusCode: statusCode)
	}

	public static func statusCode(fromWebSocketErrorDescription description: String) -> Int {
		let unexpectedServerResponsePrefix = "Unexpected server response: "
		if description.contains(unexpectedServerResponsePrefix),
		   let codeText = description.components(separatedBy: unexpectedServerResponsePrefix).last,
		   let code = Int(codeText),
		   code >= 400 {
			return code
		}

		if description.contains("timed out") || description.contains("code: E") || description.hasPrefix("E") {
			return DisconnectReasonCode.timedOut
		}

		return 500
	}

	/// The status code a login `<failure>` carries in its `reason`.
	public static func statusCode(fromFailure node: BinaryNode) -> Int {
		Int(node.attrs["reason"] ?? "") ?? DisconnectReasonCode.badSession
	}

	private static func mappedStatusCode(for reason: String, type: String?) -> Int? {
		switch reason {
		case "conflict":
			// whatsmeow: `<conflict type="device_removed"/>` is the phone unlinking this device;
			// any other conflict is another connection replacing this one.
			type == "device_removed" ? DisconnectReasonCode.loggedOut : DisconnectReasonCode.connectionReplaced
		default:
			nil
		}
	}

	private static func firstChildTag(in node: BinaryNode) -> String? {
		guard case let .nodes(children) = node.content else {
			return nil
		}

		return children.first?.tag
	}

	private static func firstChildType(in node: BinaryNode) -> String? {
		guard case let .nodes(children) = node.content else {
			return nil
		}

		return children.first?.attrs["type"]
	}
}
