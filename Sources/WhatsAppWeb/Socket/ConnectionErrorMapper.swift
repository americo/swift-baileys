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
			?? mappedStatusCode(for: rawReason)
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

	private static func mappedStatusCode(for reason: String) -> Int? {
		switch reason {
		case "conflict":
			DisconnectReasonCode.connectionReplaced
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
}
