import Foundation

public struct MessageDecryptionFailure: Equatable, Sendable {
	public let id: String?
	public let from: String?
	public let participant: String?
	public let timestamp: UInt64?
	public let ciphertextType: String?
	public let reason: MessageDecryptionFailureReason

	public init(
		id: String?,
		from: String?,
		participant: String?,
		timestamp: UInt64?,
		ciphertextType: String?,
		reason: MessageDecryptionFailureReason
	) {
		self.id = id
		self.from = from
		self.participant = participant
		self.timestamp = timestamp
		self.ciphertextType = ciphertextType
		self.reason = reason
	}
}

public enum MessageDecryptionFailureReason: Equatable, Sendable {
	case invalidSignalAddress
	case invalidGroupJID
	case emptyCiphertext
	case invalidPadding
	case emptyPaddedMessage
	case unsupportedDirectCiphertextType(String)
	case decryptionError(String)
}

public struct MessageRetryResendFailure: Equatable, Sendable {
	public let request: MessageRetryRequest
	public let reason: MessageRetryResendFailureReason

	public init(request: MessageRetryRequest, reason: MessageRetryResendFailureReason) {
		self.request = request
		self.reason = reason
	}
}

public enum MessageRetryResendFailureReason: Equatable, Sendable {
	case missingDependency(WhatsAppClientMessageDependency)
	case missingMessageDestination
	case missingReceiptMessageIDs
	case resendError(String)
}
