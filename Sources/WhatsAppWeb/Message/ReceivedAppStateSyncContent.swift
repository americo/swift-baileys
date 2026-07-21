import Foundation

public struct ReceivedAppStateSyncKeyShareContent: Equatable, Sendable {
	public let keys: [ReceivedAppStateSyncKeyContent]

	public init(keys: [ReceivedAppStateSyncKeyContent]) {
		self.keys = keys
	}
}

public struct ReceivedAppStateSyncKeyRequestContent: Equatable, Sendable {
	public let keyIDs: [ReceivedAppStateSyncKeyIDContent]

	public init(keyIDs: [ReceivedAppStateSyncKeyIDContent]) {
		self.keyIDs = keyIDs
	}
}

public struct ReceivedAppStateSyncKeyIDContent: Equatable, Sendable {
	public let keyID: Data?
	public let keyIDBase64: String?

	public init(
		keyID: Data?,
		keyIDBase64: String?
	) {
		self.keyID = keyID
		self.keyIDBase64 = keyIDBase64
	}
}

public struct ReceivedAppStateSyncKeyContent: Equatable, Sendable {
	public let keyID: Data?
	public let keyIDBase64: String?
	public let keyData: Data?
	public let fingerprint: ReceivedAppStateSyncKeyFingerprintContent?
	public let timestamp: Int64?

	public init(
		keyID: Data?,
		keyIDBase64: String?,
		keyData: Data?,
		fingerprint: ReceivedAppStateSyncKeyFingerprintContent?,
		timestamp: Int64?
	) {
		self.keyID = keyID
		self.keyIDBase64 = keyIDBase64
		self.keyData = keyData
		self.fingerprint = fingerprint
		self.timestamp = timestamp
	}
}

public struct ReceivedAppStateSyncKeyFingerprintContent: Equatable, Sendable {
	public let rawID: UInt32?
	public let currentIndex: UInt32?
	public let deviceIndexes: [UInt32]

	public init(
		rawID: UInt32?,
		currentIndex: UInt32?,
		deviceIndexes: [UInt32]
	) {
		self.rawID = rawID
		self.currentIndex = currentIndex
		self.deviceIndexes = deviceIndexes
	}
}
