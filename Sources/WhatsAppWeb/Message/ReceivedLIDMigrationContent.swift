public struct ReceivedLIDMigrationMappingSyncContent: Equatable, Sendable {
	public let chatDBMigrationTimestamp: UInt64?
	public let mappings: [ReceivedLIDMigrationMappingContent]

	public init(
		chatDBMigrationTimestamp: UInt64?,
		mappings: [ReceivedLIDMigrationMappingContent]
	) {
		self.chatDBMigrationTimestamp = chatDBMigrationTimestamp
		self.mappings = mappings
	}
}

public struct ReceivedLIDMigrationMappingContent: Equatable, Sendable {
	public let phoneNumber: String
	public let lid: String
	public let rawPhoneNumber: UInt64
	public let assignedLID: UInt64
	public let latestLID: UInt64?

	public init(
		phoneNumber: String,
		lid: String,
		rawPhoneNumber: UInt64,
		assignedLID: UInt64,
		latestLID: UInt64?
	) {
		self.phoneNumber = phoneNumber
		self.lid = lid
		self.rawPhoneNumber = rawPhoneNumber
		self.assignedLID = assignedLID
		self.latestLID = latestLID
	}
}
