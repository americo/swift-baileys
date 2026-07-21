import Foundation

public struct ReceivedMessageUpdate: Equatable, Sendable {
	public let key: WhatsAppMessageKey
	public let status: ReceivedMessageStatus?
	public let timestamp: UInt64?
	public let content: ReceivedMessageContent?
	public let stub: ReceivedMessageStubContent?
	public let protocolMessageKey: WhatsAppMessageKey?
	public let protocolAction: ReceivedMessageProtocolUpdateAction?
	public let starred: Bool?

	public init(
		key: WhatsAppMessageKey,
		status: ReceivedMessageStatus?,
		timestamp: UInt64?,
		content: ReceivedMessageContent? = nil,
		stub: ReceivedMessageStubContent? = nil,
		protocolMessageKey: WhatsAppMessageKey? = nil,
		protocolAction: ReceivedMessageProtocolUpdateAction? = nil,
		starred: Bool? = nil
	) {
		self.key = key
		self.status = status
		self.timestamp = timestamp
		self.content = content
		self.stub = stub
		self.protocolMessageKey = protocolMessageKey
		self.protocolAction = protocolAction
		self.starred = starred
	}
}

public enum ReceivedMessageProtocolUpdateAction: Equatable, Sendable {
	case revoke
	case edit
	case ephemeralSetting
}

public struct ReceivedMessageReceiptUpdate: Equatable, Sendable {
	public let key: WhatsAppMessageKey
	public let receipt: ReceivedMessageUserReceipt

	public init(key: WhatsAppMessageKey, receipt: ReceivedMessageUserReceipt) {
		self.key = key
		self.receipt = receipt
	}
}

public struct ReceivedMessageUserReceipt: Equatable, Sendable {
	public let userJID: String
	public let receiptTimestamp: UInt64?
	public let readTimestamp: UInt64?

	public init(userJID: String, receiptTimestamp: UInt64?, readTimestamp: UInt64?) {
		self.userJID = userJID
		self.receiptTimestamp = receiptTimestamp
		self.readTimestamp = readTimestamp
	}
}
