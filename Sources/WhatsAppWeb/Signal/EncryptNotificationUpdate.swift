import Foundation

let minimumPreKeyCount = 5

public protocol PreKeyUploading: Sendable {
	func uploadPreKeys(count: Int) async throws
}

public struct SignalPreKeyUploadRequest: Equatable, Sendable {
	public let currentCount: Int?
	public let requestedUploadCount: Int
	public let nativeUploadRequest: SignalNativePreKeyUploadRequest?

	public init(
		currentCount: Int? = nil,
		requestedUploadCount: Int,
		nativeUploadRequest: SignalNativePreKeyUploadRequest? = nil
	) {
		self.currentCount = currentCount
		self.requestedUploadCount = requestedUploadCount
		self.nativeUploadRequest = nativeUploadRequest
	}
}

public protocol SignalPreKeyUploading: PreKeyUploading {
	func uploadPreKeys(_ request: SignalPreKeyUploadRequest) async throws
}

public extension SignalPreKeyUploading {
	func uploadPreKeys(count: Int) async throws {
		try await uploadPreKeys(SignalPreKeyUploadRequest(requestedUploadCount: count))
	}
}

public struct PreKeyCountUpdate: Equatable, Sendable {
	public let count: Int
	public let shouldUploadMorePreKeys: Bool

	public init(count: Int, shouldUploadMorePreKeys: Bool) {
		self.count = count
		self.shouldUploadMorePreKeys = shouldUploadMorePreKeys
	}
}

public struct PreKeyUploadFailure: Equatable, Sendable {
	public let currentCount: Int
	public let requestedUploadCount: Int
	public let reason: String
	public let failureReason: PreKeyUploadFailureReason

	public init(
		currentCount: Int,
		requestedUploadCount: Int,
		reason: String,
		failureReason: PreKeyUploadFailureReason? = nil
	) {
		self.currentCount = currentCount
		self.requestedUploadCount = requestedUploadCount
		self.reason = reason
		self.failureReason = failureReason ?? .uploadError(reason)
	}
}

public enum PreKeyUploadFailureReason: Equatable, Sendable {
	case missingAuthenticationState
	case uploadError(String)
}

public enum IdentityChangeAction: Equatable, Sendable {
	case noIdentityNode
	case invalidNotification
	case skippedCompanionDevice
	case skippedSelfPrimary
	case skippedOffline
	case noSessionPreparer
	case sessionRefreshRequested
	case sessionRefreshFailed
}

public struct IdentityChangeUpdate: Equatable, Sendable {
	public let jid: String
	public let action: IdentityChangeAction

	public init(jid: String, action: IdentityChangeAction) {
		self.jid = jid
		self.action = action
	}
}
