import Foundation

public enum JIDServer: String, Sendable {
	case user = "s.whatsapp.net"
	case legacyUser = "c.us"
	case group = "g.us"
	case broadcast
	case call
	case lid
	case newsletter
	case bot
	case hosted
	case hostedLid = "hosted.lid"
}

public enum JIDDomainType: Int, Sendable {
	case whatsapp = 0
	case lid = 1
	case hosted = 128
	case hostedLid = 129
}

public struct JID: Hashable, Sendable {
	public let user: String
	public let server: String
	public let device: Int?
	public let domainType: JIDDomainType

	public init(user: String, server: String, device: Int? = nil, domainType: JIDDomainType = .whatsapp) {
		self.user = user
		self.server = server
		self.device = device
		self.domainType = domainType
	}

	public init?(_ rawValue: String?) {
		guard let rawValue, let separatorIndex = rawValue.firstIndex(of: "@") else {
			return nil
		}

		let userAndDevice = String(rawValue[..<separatorIndex])
		let server = String(rawValue[rawValue.index(after: separatorIndex)...])
		let userParts = userAndDevice.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
		let agentParts = userParts[0].split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
		let agent = agentParts.count > 1 ? Int(agentParts[1]) : nil

		self.user = String(agentParts[0])
		self.server = server
		self.device = userParts.count > 1 ? Int(userParts[1]) : nil

		switch server {
		case JIDServer.lid.rawValue:
			self.domainType = .lid
		case JIDServer.hosted.rawValue:
			self.domainType = .hosted
		case JIDServer.hostedLid.rawValue:
			self.domainType = .hostedLid
		default:
			self.domainType = agent.flatMap(JIDDomainType.init(rawValue:)) ?? .whatsapp
		}
	}

	public var rawValue: String {
		Self.encode(user: user, server: server, device: device)
	}

	public var normalizedUser: String {
		let normalizedServer = server == JIDServer.legacyUser.rawValue ? JIDServer.user.rawValue : server
		return Self.encode(user: user, server: normalizedServer)
	}

	public static func encode(user: String?, server: String, device: Int? = nil, agent: Int? = nil) -> String {
		let agentPart = agent.map { "_\($0)" } ?? ""
		let devicePart = device.map { ":\($0)" } ?? ""
		return "\(user ?? "")\(agentPart)\(devicePart)@\(server)"
	}

	public static func areSameUser(_ left: String?, _ right: String?) -> Bool {
		guard let left = JID(left), let right = JID(right) else {
			return false
		}

		return left.user == right.user
	}

	public static func transferDevice(from source: String, to destination: String) -> String? {
		guard let source = JID(source), let destination = JID(destination) else {
			return nil
		}

		return encode(user: destination.user, server: destination.server, device: source.device ?? 0)
	}
}

public extension String {
	var isWhatsAppUserJID: Bool { hasSuffix("@\(JIDServer.user.rawValue)") }
	var isLIDUserJID: Bool { hasSuffix("@\(JIDServer.lid.rawValue)") }
	var isBroadcastJID: Bool { hasSuffix("@\(JIDServer.broadcast.rawValue)") }
	var isGroupJID: Bool { hasSuffix("@\(JIDServer.group.rawValue)") }
	var isNewsletterJID: Bool { hasSuffix("@\(JIDServer.newsletter.rawValue)") }
	var isHostedUserJID: Bool { hasSuffix("@\(JIDServer.hosted.rawValue)") }
	var isHostedLIDUserJID: Bool { hasSuffix("@\(JIDServer.hostedLid.rawValue)") }
	var isStatusBroadcastJID: Bool { self == "status@broadcast" }
}
