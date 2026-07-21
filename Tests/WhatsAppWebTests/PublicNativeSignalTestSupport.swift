import Foundation
import WhatsAppWeb

actor PublicNativeSignalAdapter: WhatsAppNativeSignalAdapter, SignalNativeAccountImportChecking {
	private let existingAddresses: Set<SignalProtocolAddress>
	private let existingAccountAddresses: Set<SignalProtocolAddress>
	private let readinessError: (any Error)?
	private let accountCheckError: (any Error)?
	private let signedPreKeySignature: Data
	private(set) var checkedAddresses: [[SignalSessionAddressCheck]] = []
	private(set) var installedRequests: [SignalSessionNativeInstallRequest] = []
	private(set) var directEncryptionRequests: [SignalDirectMessageEncryptionRequest] = []
	private(set) var groupEncryptionRequests: [SignalGroupMessageEncryptionRequest] = []
	private(set) var directDecryptionRequests: [SignalDirectMessageDecryptionRequest] = []
	private(set) var groupDecryptionRequests: [SignalGroupMessageDecryptionRequest] = []
	private(set) var senderKeyDistributionRequests: [SenderKeyDistributionMessageRequest] = []
	private(set) var preKeyUploadRequests: [SignalPreKeyUploadRequest] = []
	private(set) var accountImportRequests: [SignalNativeAccountImportRequest] = []
	private(set) var accountCheckRequests: [SignalNativeAccountImportRequest] = []
	private(set) var readinessCheckCount = 0
	nonisolated private let signedPreKeySignatureRecorder =
		PublicNativeRequestRecorder<SignalSignedPreKeySignatureRequest>()
	nonisolated var signedPreKeySignatureRequests: [SignalSignedPreKeySignatureRequest] {
		signedPreKeySignatureRecorder.values
	}

	init(
		existingAddresses: Set<SignalProtocolAddress>,
		existingAccountAddresses: Set<SignalProtocolAddress> = [],
		readinessError: (any Error)? = nil,
		accountCheckError: (any Error)? = nil,
		signedPreKeySignature: Data = Data(repeating: 0x51, count: 64)
	) {
		self.existingAddresses = existingAddresses
		self.existingAccountAddresses = existingAccountAddresses
		self.readinessError = readinessError
		self.accountCheckError = accountCheckError
		self.signedPreKeySignature = signedPreKeySignature
	}

	func encryptMessage(_ request: SignalDirectMessageEncryptionRequest) async throws -> EncryptedMessage {
		directEncryptionRequests.append(request)
		return EncryptedMessage(type: "msg", ciphertext: request.data)
	}

	func encryptGroupMessage(_ request: SignalGroupMessageEncryptionRequest) async throws -> EncryptedGroupMessage {
		groupEncryptionRequests.append(request)
		return EncryptedGroupMessage(ciphertext: request.data, senderKeyDistributionMessage: Data([0x11, 0x22]))
	}

	func decryptMessage(_ request: SignalDirectMessageDecryptionRequest) async throws -> Data {
		directDecryptionRequests.append(request)
		return request.ciphertext
	}

	func decryptGroupMessage(_ request: SignalGroupMessageDecryptionRequest) async throws -> Data {
		groupDecryptionRequests.append(request)
		return request.ciphertext
	}

	func processSenderKeyDistributionMessage(_ request: SenderKeyDistributionMessageRequest) async throws {
		senderKeyDistributionRequests.append(request)
	}

	func installSession(_ request: SignalSessionNativeInstallRequest) async throws {
		installedRequests.append(request)
	}

	func existingSessions(for checks: [SignalSessionAddressCheck]) async throws -> Set<SignalProtocolAddress> {
		checkedAddresses.append(checks)
		return Set(checks.map(\.address).filter(existingAddresses.contains))
	}

	func uploadPreKeys(_ request: SignalPreKeyUploadRequest) async throws {
		preKeyUploadRequests.append(request)
	}

	func assertReadyForSignalOperations() async throws {
		readinessCheckCount += 1
		if let readinessError {
			throw readinessError
		}
	}

	func importAccount(_ request: SignalNativeAccountImportRequest) async throws {
		accountImportRequests.append(request)
	}

	func containsAccount(_ request: SignalNativeAccountImportRequest) async throws -> Bool {
		accountCheckRequests.append(request)
		if let accountCheckError {
			throw accountCheckError
		}
		return existingAccountAddresses.contains(request.localAddress)
	}

	nonisolated func signSignedPreKey(_ request: SignalSignedPreKeySignatureRequest) throws -> Data {
		signedPreKeySignatureRecorder.record(request)
		return signedPreKeySignature
	}
}

final class PublicNativeRequestRecorder<Value: Sendable>: @unchecked Sendable {
	private let lock = NSLock()
	private var recordedValues: [Value] = []

	var values: [Value] {
		lock.withLock {
			recordedValues
		}
	}

	func record(_ value: Value) {
		lock.withLock {
			recordedValues.append(value)
		}
	}
}

final class PublicNativeAuthenticationKeyPairSequence: @unchecked Sendable {
	private let lock = NSLock()
	private var keyPairs: [AuthenticationKeyPair]

	init(_ keyPairs: [AuthenticationKeyPair]) {
		self.keyPairs = keyPairs
	}

	func next() -> AuthenticationKeyPair {
		lock.withLock {
			keyPairs.removeFirst()
		}
	}
}

actor PublicNativeSignalTransport: WhatsAppWebSocketTransport {
	private let respondsToQueries: Bool
	private(set) var sentFrames: [Data] = []
	private(set) var sentNodes: [BinaryNode] = []
	private var inboundContinuations: [CheckedContinuation<Data?, Error>] = []
	private var inboundFrames: [Data?] = []

	init(respondsToQueries: Bool = false) {
		self.respondsToQueries = respondsToQueries
	}

	func connect() async throws {}

	func send(_ data: Data) async throws {
		sentFrames.append(data)
		guard respondsToQueries else {
			return
		}

		var codec = NoiseFrameCodec()
		let payloads = codec.decode(data)
		for payload in payloads {
			let node = try BinaryNodeDecoder().decode(payload)
			sentNodes.append(node)
			guard node.tag == "iq", let id = node.attrs["id"] else {
				continue
			}

			let response = try await publicNativeDependencyQuery(node, .seconds(60))
			enqueue(response.withID(id))
		}
	}

	func receive() async throws -> Data? {
		try await withCheckedThrowingContinuation { continuation in
			if !inboundFrames.isEmpty {
				continuation.resume(returning: inboundFrames.removeFirst())
			} else {
				inboundContinuations.append(continuation)
			}
		}
	}

	func close() async {
		resume(nil)
	}

	func enqueueIncoming(_ node: BinaryNode) {
		enqueue(node)
	}

	private func enqueue(_ node: BinaryNode) {
		var codec = NoiseFrameCodec()
		resume(codec.encode(try! BinaryNodeEncoder().encode(node)))
	}

	private func resume(_ data: Data?) {
		if inboundContinuations.isEmpty {
			inboundFrames.append(data)
		} else {
			inboundContinuations.removeFirst().resume(returning: data)
		}
	}
}

extension BinaryNode {
	func withID(_ id: String) -> BinaryNode {
		BinaryNode(
			tag: tag,
			attrs: BinaryNode.Attributes(attrs.orderedEntries + [("id", id)]),
			content: content
		)
	}
}

func publicNativeEncodedText(_ text: String) throws -> Data {
	let textData = Data(text.utf8)
	var data = Data([0x32, UInt8(textData.count + 2), 0x0a, UInt8(textData.count)])
	data.append(textData)
	data.append(1)
	return data
}

func publicNativeEncodedText(
	_ text: String,
	senderKeyDistribution: Data,
	senderKeyDistributionFieldTag: UInt8 = 0x12
) throws -> Data {
	let textData = Data(text.utf8)
	let extendedText = Data([0x0a, UInt8(textData.count)]) + textData
	var data = Data([senderKeyDistributionFieldTag, UInt8(senderKeyDistribution.count)])
	data.append(senderKeyDistribution)
	data.append(contentsOf: [0x32, UInt8(extendedText.count)])
	data.append(extendedText)
	data.append(1)
	return data
}

func publicNativeSenderKeyDistribution(groupID: String, senderKey: Data) -> Data {
	let groupData = Data(groupID.utf8)
	var data = Data([0x0a, UInt8(groupData.count)])
	data.append(groupData)
	data.append(contentsOf: [0x12, UInt8(senderKey.count)])
	data.append(senderKey)
	return data
}

func publicNativePairedCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
		signedIdentityKey: AuthenticationKeyPair(
			privateKey: Data([5]),
			publicKey: Data([5]) + Data(repeating: 6, count: 32)
		),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(
				privateKey: Data([7]),
				publicKey: Data([5]) + Data(repeating: 8, count: 32)
			),
			signature: Data(repeating: 9, count: 64),
			keyID: 10
		),
		registrationID: 11,
		advSecretKey: "secret",
		me: WhatsAppUser(id: "999:0@s.whatsapp.net"),
		nextPreKeyID: 12,
		firstUnuploadedPreKeyID: 13,
		accountSyncCounter: 0,
		registered: true
	)
}

func publicNativeWaitForSentNodes(_ count: Int, in transport: PublicNativeSignalTransport) async -> [BinaryNode] {
	for _ in 0..<50 {
		let nodes = await transport.sentNodes
		if nodes.count >= count { return nodes }
		try? await Task.sleep(for: .milliseconds(10))
	}
	return await transport.sentNodes
}

func publicNativeDependencyQuery(_ node: BinaryNode, _ timeout: Duration) async throws -> BinaryNode {
	if node.attrs["xmlns"] == "usync" {
		return BinaryNode(
			tag: "iq",
			attrs: ["type": "result"],
			content: .nodes([
				BinaryNode(
					tag: "usync",
					content: .nodes([
						BinaryNode(
							tag: "list",
							content: .nodes([
								BinaryNode(
									tag: "user",
									attrs: ["jid": "123@s.whatsapp.net"],
									content: .nodes([
										BinaryNode(
											tag: "devices",
											content: .nodes([
												BinaryNode(
													tag: "device-list",
													content: .nodes([
														BinaryNode(tag: "device", attrs: ["id": "0"]),
														BinaryNode(tag: "device", attrs: ["id": "1", "key-index": "7"])
													])
												)
											])
										)
									])
								)
							])
						)
					])
				)
			])
		)
	}

	let requestedJIDs = node.firstChild(named: "key")?.children(named: "user").compactMap { $0.attrs["jid"] } ?? []
	return BinaryNode(
		tag: "iq",
		attrs: ["type": "result"],
		content: .nodes([
			BinaryNode(
				tag: "list",
				content: .nodes(requestedJIDs.map(signalBundleUser))
			)
		])
	)
}

private func signalBundleUser(jid: String) -> BinaryNode {
	BinaryNode(
		tag: "user",
		attrs: ["jid": jid],
		content: .nodes([
			BinaryNode(tag: "registration", content: .data(Data([0, 0, 0, 1]))),
			BinaryNode(tag: "identity", content: .data(Data(repeating: 0x11, count: 32))),
			preKeyNode(tag: "skey", id: 1, value: 0x22, signature: Data(repeating: 0x33, count: 64)),
			preKeyNode(tag: "key", id: 2, value: 0x44)
		])
	)
}

private func preKeyNode(tag: String, id: Int, value: UInt8, signature: Data? = nil) -> BinaryNode {
	var children = [
		BinaryNode(tag: "id", content: .data(Data([0, 0, UInt8(id)]))),
		BinaryNode(tag: "value", content: .data(Data(repeating: value, count: 32)))
	]
	if let signature {
		children.append(BinaryNode(tag: "signature", content: .data(signature)))
	}

	return BinaryNode(tag: tag, content: .nodes(children))
}
