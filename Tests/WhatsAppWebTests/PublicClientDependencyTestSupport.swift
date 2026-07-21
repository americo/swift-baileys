import Foundation
import WhatsAppWeb

actor PublicMessageEncryptor: MessageEncrypting {
	func encryptMessage(jid: String, data: Data) async throws -> EncryptedMessage {
		EncryptedMessage(type: "msg", ciphertext: data)
	}
}

struct PublicDeviceResolver: MessageDeviceResolving {
	func deviceJIDs(for jid: String) async throws -> [String] {
		[jid]
	}
}

struct PublicSessionPreparer: SignalSessionPreparing {
	func assertSessions(for jids: [String], force: Bool) async throws -> Bool {
		!jids.isEmpty
	}
}

struct PublicMediaUploader: WhatsAppMediaUploading {
	func upload(_ data: Data, fileEncSha256Base64: String, mediaType: MediaType) async throws -> MediaUploadResult {
		MediaUploadResult(mediaURL: "https://media.example/file", directPath: "/file")
	}
}

actor PublicPreKeyUploader: PreKeyUploading {
	private(set) var calls: [Int] = []

	func uploadPreKeys(count: Int) async throws {
		calls.append(count)
	}
}

actor PublicSignalPreKeyUploader: SignalPreKeyUploading {
	private(set) var requests: [SignalPreKeyUploadRequest] = []

	func uploadPreKeys(_ request: SignalPreKeyUploadRequest) async throws {
		requests.append(request)
	}
}

struct PublicSignalDecryptor: SignalMessageDecrypting {
	func decryptMessage(jid: String, type: String, ciphertext: Data) async throws -> Data {
		ciphertext
	}

	func decryptGroupMessage(group: String, authorJID: String, ciphertext: Data) async throws -> Data {
		ciphertext
	}

	func processSenderKeyDistributionMessage(authorJID: String, messageData: Data) async throws {}
}

actor PublicMediaUploadTransport: MediaUploading {
	private let result: MediaUploadTransportResult
	private(set) var requests: [MediaUploadRequest] = []

	init(result: MediaUploadTransportResult) {
		self.result = result
	}

	func upload(data: Data, request: MediaUploadRequest) async throws -> MediaUploadTransportResult? {
		requests.append(request)
		return result
	}
}

struct PublicBundleResolver: SignalBundleResolving {
	func fetchBundles(for jids: [String], force: Bool) async throws -> [SignalSessionBundle] {
		jids.map { jid in
			SignalSessionBundle(
				jid: jid,
				registrationID: 1,
				identityKey: Data([5]) + Data(repeating: 1, count: 32),
				signedPreKey: SignalPreKey(
					keyID: 2,
					publicKey: Data([5]) + Data(repeating: 2, count: 32),
					signature: Data(repeating: 3, count: 64)
				),
				preKey: SignalPreKey(keyID: 3, publicKey: Data([5]) + Data(repeating: 4, count: 32))
			)
		}
	}
}

actor PublicSessionInjector: SignalSessionInjecting {
	private(set) var bundles: [SignalSessionBundle] = []

	func injectSession(bundle: SignalSessionBundle) async throws {
		bundles.append(bundle)
	}
}

actor PublicSessionChecker: SignalSessionChecking {
	private let existingJIDs: Set<String>
	private(set) var calls: [[String]] = []

	init(existingJIDs: Set<String>) {
		self.existingJIDs = existingJIDs
	}

	func existingSessions(for jids: [String]) async throws -> Set<String> {
		calls.append(jids)
		return Set(jids.filter(existingJIDs.contains))
	}
}

actor PublicSessionAddressChecker: SignalSessionAddressChecking {
	private let existingAddresses: Set<SignalProtocolAddress>
	private(set) var calls: [[SignalSessionAddressCheck]] = []

	init(existingAddresses: Set<SignalProtocolAddress>) {
		self.existingAddresses = existingAddresses
	}

	func existingSessions(for checks: [SignalSessionAddressCheck]) async throws -> Set<SignalProtocolAddress> {
		calls.append(checks)
		return Set(checks.map(\.address).filter(existingAddresses.contains))
	}
}

actor PublicSignalAdapter: WhatsAppSignalAdapter {
	private let existingJIDs: Set<String>
	private(set) var checkedJIDs: [[String]] = []
	private(set) var injectedBundles: [SignalSessionBundle] = []

	init(existingJIDs: Set<String>) {
		self.existingJIDs = existingJIDs
	}

	func encryptMessage(jid: String, data: Data) async throws -> EncryptedMessage {
		EncryptedMessage(type: "msg", ciphertext: data)
	}

	func encryptGroupMessage(group: String, senderJID: String, data: Data) async throws -> EncryptedGroupMessage {
		EncryptedGroupMessage(ciphertext: data, senderKeyDistributionMessage: Data([0x11, 0x22]))
	}

	func decryptMessage(jid: String, type: String, ciphertext: Data) async throws -> Data {
		ciphertext
	}

	func decryptGroupMessage(group: String, authorJID: String, ciphertext: Data) async throws -> Data {
		ciphertext
	}

	func processSenderKeyDistributionMessage(authorJID: String, messageData: Data) async throws {}

	func injectSession(bundle: SignalSessionBundle) async throws {
		injectedBundles.append(bundle)
	}

	func existingSessions(for jids: [String]) async throws -> Set<String> {
		checkedJIDs.append(jids)
		return Set(jids.filter(existingJIDs.contains))
	}
}

func publicDependencyQuery(_ node: BinaryNode, _ timeout: Duration) async throws -> BinaryNode {
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

	if node.attrs["xmlns"] == "w:m" {
		return BinaryNode(
			tag: "iq",
			attrs: ["type": "result"],
			content: .nodes([
				BinaryNode(
					tag: "media_conn",
					attrs: ["auth": "media-auth", "ttl": "1200"],
					content: .nodes([
						BinaryNode(tag: "host", attrs: [
							"hostname": "mmg.whatsapp.net",
							"maxContentLengthBytes": "1048576"
						])
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
				content: .nodes(requestedJIDs.map(publicDependencySignalBundleUser))
			)
		])
	)
}

private func publicDependencySignalBundleUser(jid: String) -> BinaryNode {
	BinaryNode(
		tag: "user",
		attrs: ["jid": jid],
		content: .nodes([
			BinaryNode(tag: "registration", content: .data(Data([0, 0, 0, 1]))),
			BinaryNode(tag: "identity", content: .data(Data(repeating: 0x11, count: 32))),
			publicDependencyPreKeyNode(tag: "skey", id: 1, value: 0x22, signature: Data(repeating: 0x33, count: 64)),
			publicDependencyPreKeyNode(tag: "key", id: 2, value: 0x44)
		])
	)
}

private func publicDependencyPreKeyNode(tag: String, id: Int, value: UInt8, signature: Data? = nil) -> BinaryNode {
	var children = [
		BinaryNode(tag: "id", content: .data(Data([0, 0, UInt8(id)]))),
		BinaryNode(tag: "value", content: .data(Data(repeating: value, count: 32)))
	]
	if let signature {
		children.append(BinaryNode(tag: "signature", content: .data(signature)))
	}

	return BinaryNode(tag: tag, content: .nodes(children))
}
