import Foundation

public protocol WhatsAppSignalAdapter:
	MessageEncrypting,
	GroupMessageEncrypting,
	SignalMessageDecrypting,
	SignalSessionInjecting,
	SignalSessionChecking {}

public protocol SignalNativeOperationReadinessChecking: Sendable {
	func assertReadyForSignalOperations() async throws
}

public protocol WhatsAppNativeSignalAdapter:
	SignalAddressedMessageEncrypting,
	SignalAddressedGroupMessageEncrypting,
	SignalAddressedMessageDecrypting,
	SignalNativeOperationReadinessChecking,
	SignalSignedPreKeySigning,
	SignalNativeAccountImporting,
	SignalNativeAccountImportChecking,
	MessageEncrypting,
	GroupMessageEncrypting,
	SignalMessageDecrypting,
	SignalNativeSessionInstalling,
	SignalSessionAddressChecking,
	SignalPreKeyUploading {}

public extension WhatsAppNativeSignalAdapter {
	func encryptMessage(jid: String, data: Data) async throws -> EncryptedMessage {
		try await encryptMessage(SignalDirectMessageEncryptionRequest(jid: jid, data: data))
	}

	func encryptGroupMessage(group: String, senderJID: String, data: Data) async throws -> EncryptedGroupMessage {
		try await encryptGroupMessage(SignalGroupMessageEncryptionRequest(
			groupJID: group,
			senderJID: senderJID,
			data: data
		))
	}

	func decryptMessage(jid: String, type: String, ciphertext: Data) async throws -> Data {
		try await decryptMessage(SignalDirectMessageDecryptionRequest(
			jid: jid,
			type: type,
			ciphertext: ciphertext
		))
	}

	func decryptGroupMessage(group: String, authorJID: String, ciphertext: Data) async throws -> Data {
		try await decryptGroupMessage(SignalGroupMessageDecryptionRequest(
			groupJID: group,
			authorJID: authorJID,
			ciphertext: ciphertext
		))
	}

	func processSenderKeyDistributionMessage(authorJID: String, messageData: Data) async throws {
		try await processSenderKeyDistributionMessage(SenderKeyDistributionMessageRequest(
			authorJID: authorJID,
			messageData: messageData
		))
	}
}

public struct WhatsAppClientMessageDependencies: Sendable {
	public typealias Query = @Sendable (_ node: BinaryNode, _ timeout: Duration) async throws -> BinaryNode

	public let messageEncryptor: any MessageEncrypting
	public let groupMessageEncryptor: (any GroupMessageEncrypting)?
	public let messageDeviceResolver: any MessageDeviceResolving
	public let signalSessionPreparer: any SignalSessionPreparing
	public let retrySessionInjector: (any SignalSessionInjecting)?
	public let mediaUploader: (any WhatsAppMediaUploading)?
	public let incomingSignalDecryptor: (any SignalMessageDecrypting)?
	public let preKeyUploader: (any PreKeyUploading)?

	public init(
		messageEncryptor: any MessageEncrypting,
		groupMessageEncryptor: (any GroupMessageEncrypting)? = nil,
		messageDeviceResolver: any MessageDeviceResolving,
		signalSessionPreparer: any SignalSessionPreparing,
		retrySessionInjector: (any SignalSessionInjecting)? = nil,
		mediaUploader: (any WhatsAppMediaUploading)? = nil,
		incomingSignalDecryptor: (any SignalMessageDecrypting)? = nil,
		preKeyUploader: (any PreKeyUploading)? = nil
	) {
		self.messageEncryptor = messageEncryptor
		self.groupMessageEncryptor = groupMessageEncryptor
		self.messageDeviceResolver = messageDeviceResolver
		self.signalSessionPreparer = signalSessionPreparer
		self.retrySessionInjector = retrySessionInjector
		self.mediaUploader = mediaUploader
		self.incomingSignalDecryptor = incomingSignalDecryptor
		self.preKeyUploader = preKeyUploader
	}

	public init(
		messageEncryptor: any MessageEncrypting,
		groupMessageEncryptor: (any GroupMessageEncrypting)? = nil,
		signalKeys: any SignalKeyStore,
		sessionInjector: any SignalSessionInjecting,
		sessionChecker: (any SignalSessionChecking)? = nil,
		query: @escaping Query,
		mediaUploader: (any WhatsAppMediaUploading)? = nil,
		incomingSignalDecryptor: (any SignalMessageDecrypting)? = nil,
		preKeyUploader: (any PreKeyUploading)? = nil
	) {
		let bundleResolver = SignalSessionBundleResolver(query: query)
		let sessionPreparer: any SignalSessionPreparing
		if let sessionChecker {
			sessionPreparer = SignalSessionPreparer(
				sessionChecker: sessionChecker,
				bundleResolver: bundleResolver,
				sessionInjector: sessionInjector
			)
		} else {
			sessionPreparer = SignalSessionPreparer(
				keys: signalKeys,
				bundleResolver: bundleResolver,
				sessionInjector: sessionInjector
			)
		}

		self.init(
			messageEncryptor: messageEncryptor,
			groupMessageEncryptor: groupMessageEncryptor,
			messageDeviceResolver: USyncMessageDeviceResolver(query: query),
			signalSessionPreparer: sessionPreparer,
			retrySessionInjector: sessionInjector,
			mediaUploader: mediaUploader,
			incomingSignalDecryptor: incomingSignalDecryptor,
			preKeyUploader: preKeyUploader
		)
	}

	public init(
		signalAdapter: any WhatsAppSignalAdapter,
		query: @escaping Query,
		mediaUploader: (any WhatsAppMediaUploading)? = nil,
		preKeyUploader: (any PreKeyUploading)? = nil
	) {
		let bundleResolver = SignalSessionBundleResolver(query: query)
		let sessionPreparer = SignalSessionPreparer(
			sessionChecker: signalAdapter,
			bundleResolver: bundleResolver,
			sessionInjector: signalAdapter
		)

		self.init(
			messageEncryptor: signalAdapter,
			groupMessageEncryptor: signalAdapter,
			messageDeviceResolver: USyncMessageDeviceResolver(query: query),
			signalSessionPreparer: sessionPreparer,
			retrySessionInjector: signalAdapter,
			mediaUploader: mediaUploader,
			incomingSignalDecryptor: signalAdapter,
			preKeyUploader: preKeyUploader
		)
	}

	public init(
		nativeSignalAdapter: any WhatsAppNativeSignalAdapter,
		query: @escaping Query,
		mediaUploader: (any WhatsAppMediaUploading)? = nil,
		localJID: String? = nil
	) {
		self.init(
			nativeSignalAdapter: nativeSignalAdapter,
			query: query,
			mediaUploader: mediaUploader,
			localJIDProvider: { localJID }
		)
	}

	public init(
		nativeSignalAdapter: any WhatsAppNativeSignalAdapter,
		query: @escaping Query,
		mediaUploader: (any WhatsAppMediaUploading)? = nil,
		localJIDProvider: @escaping @Sendable () async -> String?
	) {
		let bundleResolver = SignalSessionBundleResolver(query: query)
		let sessionPreparer = SignalSessionPreparer(
			addressChecker: nativeSignalAdapter,
			bundleResolver: bundleResolver,
			sessionInjector: nativeSignalAdapter,
			localJIDProvider: localJIDProvider
		)

		self.init(
			messageEncryptor: nativeSignalAdapter,
			groupMessageEncryptor: nativeSignalAdapter,
			messageDeviceResolver: USyncMessageDeviceResolver(query: query),
			signalSessionPreparer: sessionPreparer,
			retrySessionInjector: nativeSignalAdapter,
			mediaUploader: mediaUploader,
			incomingSignalDecryptor: nativeSignalAdapter,
			preKeyUploader: nativeSignalAdapter
		)
	}

	public init(
		signalAdapter: any WhatsAppSignalAdapter,
		signalKeys: any SignalKeyStore,
		query: @escaping Query,
		mediaUploader: (any WhatsAppMediaUploading)? = nil,
		preKeyUploader: (any PreKeyUploading)? = nil
	) {
		self.init(
			messageEncryptor: signalAdapter,
			groupMessageEncryptor: signalAdapter,
			signalKeys: signalKeys,
			sessionInjector: signalAdapter,
			sessionChecker: signalAdapter,
			query: query,
			mediaUploader: mediaUploader,
			incomingSignalDecryptor: signalAdapter,
			preKeyUploader: preKeyUploader
		)
	}
}
