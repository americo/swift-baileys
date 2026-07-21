import Foundation

public struct NewsletterReactionUpdate: Equatable, Sendable {
	public let id: String
	public let serverID: String
	public let code: String?
	public let count: Int

	public init(id: String, serverID: String, code: String?, count: Int) {
		self.id = id
		self.serverID = serverID
		self.code = code
		self.count = count
	}
}

public struct NewsletterViewUpdate: Equatable, Sendable {
	public let id: String
	public let serverID: String
	public let count: Int

	public init(id: String, serverID: String, count: Int) {
		self.id = id
		self.serverID = serverID
		self.count = count
	}
}

public struct NewsletterParticipantUpdate: Equatable, Sendable {
	public let id: String
	public let author: String
	public let user: String
	public let action: String
	public let newRole: String

	public init(id: String, author: String, user: String, action: String, newRole: String) {
		self.id = id
		self.author = author
		self.user = user
		self.action = action
		self.newRole = newRole
	}
}

public struct NewsletterSettingsUpdate: Equatable, Sendable {
	public let id: String
	public let name: String?
	public let description: String?

	public init(id: String, name: String? = nil, description: String? = nil) {
		self.id = id
		self.name = name
		self.description = description
	}
}
