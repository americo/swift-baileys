import Foundation

public struct ReceivedEncryptedCommentContent: Equatable, Sendable {
	public let targetMessageKey: ReceivedMessageKey?
	public let encryptedPayload: Data?
	public let encryptedIV: Data?

	public init(targetMessageKey: ReceivedMessageKey?, encryptedPayload: Data?, encryptedIV: Data?) {
		self.targetMessageKey = targetMessageKey
		self.encryptedPayload = encryptedPayload
		self.encryptedIV = encryptedIV
	}
}

public struct ReceivedEncryptedReactionContent: Equatable, Sendable {
	public let targetMessageKey: ReceivedMessageKey?
	public let encryptedPayload: Data?
	public let encryptedIV: Data?

	public init(targetMessageKey: ReceivedMessageKey?, encryptedPayload: Data?, encryptedIV: Data?) {
		self.targetMessageKey = targetMessageKey
		self.encryptedPayload = encryptedPayload
		self.encryptedIV = encryptedIV
	}
}

public enum ReceivedSecretEncryptedType: Equatable, Sendable {
	case unknown
	case eventEdit
	case messageEdit
	case unrecognized(Int)
}

public struct ReceivedSecretEncryptedContent: Equatable, Sendable {
	public let targetMessageKey: ReceivedMessageKey?
	public let encryptedPayload: Data?
	public let encryptedIV: Data?
	public let type: ReceivedSecretEncryptedType?

	public init(
		targetMessageKey: ReceivedMessageKey?,
		encryptedPayload: Data?,
		encryptedIV: Data?,
		type: ReceivedSecretEncryptedType?
	) {
		self.targetMessageKey = targetMessageKey
		self.encryptedPayload = encryptedPayload
		self.encryptedIV = encryptedIV
		self.type = type
	}
}
