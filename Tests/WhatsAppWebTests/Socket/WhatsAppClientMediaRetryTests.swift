import Foundation
import CryptoKit
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client media retry")
struct WhatsAppClientMediaRetryTests {
	@Test("sends encrypted media reupload requests")
	func sendsEncryptedMediaReuploadRequests() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: mediaRetryCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()

		let node = try await client.requestMediaReupload(
			for: WhatsAppMessageKey(
				remoteJID: "123@s.whatsapp.net",
				fromMe: false,
				id: "MEDIA-CLIENT-1",
				participant: "456@s.whatsapp.net"
			),
			mediaKey: Data((0..<32).map(UInt8.init)),
			randomBytes: { count in Data(repeating: 0x09, count: count) }
		)

		let sentFrame = try await transport.waitForSentFrame()
		var codec = NoiseFrameCodec()
		let sent = try BinaryNodeDecoder().decode(codec.decode(sentFrame)[0])
		#expect(sent == node)
		#expect(sent.tag == "receipt")
		#expect(sent.attrs["id"] == "MEDIA-CLIENT-1")
		#expect(sent.attrs["to"] == "258840000100@s.whatsapp.net")
		#expect(sent.attrs["type"] == "server-error")
		#expect(try #require(sent.firstChild(named: "encrypt")?.childData(named: "enc_iv")) == Data(repeating: 0x09, count: 12))

		let rmr = try #require(sent.firstChild(named: "rmr"))
		#expect(rmr.attrs["jid"] == "123@s.whatsapp.net")
		#expect(rmr.attrs["from_me"] == "false")
		#expect(rmr.attrs["participant"] == "456@s.whatsapp.net")
	}

	@Test("requires authenticated user for media reupload requests")
	func requiresAuthenticatedUserForMediaReuploadRequests() async {
		let client = WhatsAppClient()

		await #expect(throws: WhatsAppClientError.missingAuthenticatedUser) {
			try await client.requestMediaReupload(
				for: WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "MEDIA-CLIENT-2"),
				mediaKey: Data((0..<32).map(UInt8.init)),
				randomBytes: { count in Data(repeating: 0x09, count: count) }
			)
		}

		var credentials = mediaRetryCredentials()
		credentials.me = WhatsAppUser(id: "")
		let authenticatedClient = WhatsAppClient(authenticationState: AuthenticationState(
			credentials: credentials,
			keys: InMemorySignalKeyStore()
		))
		await #expect(throws: WhatsAppClientError.missingAuthenticatedUser) {
			try await authenticatedClient.requestMediaReupload(
				for: WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "MEDIA-CLIENT-2"),
				mediaKey: Data((0..<32).map(UInt8.init)),
				randomBytes: { count in Data(repeating: 0x09, count: count) }
			)
		}
	}

	@Test("updates media download requests from successful reupload notifications")
	func updatesMediaDownloadRequestsFromSuccessfulReuploadNotifications() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: mediaRetryCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		try await client.connect()
		let request = mediaDownloadRequest(url: URL(string: "https://mmg.whatsapp.net/v/expired")!)
		let key = WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "MEDIA-CLIENT-3")

		let task = Task {
			try await client.updateMediaDownloadRequest(
				request,
				for: key,
				timeout: .seconds(2),
				randomBytes: { count in Data(repeating: 0x09, count: count) }
			)
		}
		_ = try await transport.waitForSentFrame()
		await client.handleIncomingNode(try mediaRetryNotificationNode(
			messageID: "MEDIA-CLIENT-3",
			result: .success,
			directPath: "/v/refreshed"
		))

		let updated = try await task.value
		#expect(updated == mediaDownloadRequest(url: URL(string: "https://mmg.whatsapp.net/v/refreshed")!))
	}

	@Test("Baileys updateMediaMessage alias returns refreshed media messages")
	func baileysUpdateMediaMessageAliasReturnsRefreshedMediaMessages() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: mediaRetryCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		var events = client.events.makeAsyncIterator()
		try await client.connect()
		let message = ReceivedMessage(
			id: "MEDIA-CLIENT-UPDATE",
			from: "123@s.whatsapp.net",
			timestamp: 1_700_000_000,
			content: .image(ReceivedImageContent(
				url: "https://mmg.whatsapp.net/v/expired-message",
				directPath: "/v/expired-message",
				mediaKey: Data((0..<32).map(UInt8.init)),
				fileEncSHA256: Data(repeating: 0x11, count: 32),
				fileSHA256: Data(repeating: 0x22, count: 32),
				fileLength: 128,
				mediaKeyTimestamp: 1_700_000_000,
				mimetype: "image/jpeg",
				caption: "old",
				jpegThumbnail: Data([0xaa])
			)),
			fromMe: false,
			participant: "456@s.whatsapp.net",
			pushName: "Sender"
		)

		let task = Task {
			try await client.updateMediaMessage(
				message,
				timeout: .seconds(2),
				randomBytes: { count in Data(repeating: 0x09, count: count) }
			)
		}
		_ = try await transport.waitForSentFrame()
		await client.handleIncomingNode(try mediaRetryNotificationNode(
			messageID: "MEDIA-CLIENT-UPDATE",
			result: .success,
			directPath: "/v/refreshed-message"
		))

		let updated = try await task.value
		#expect(updated.id == message.id)
		#expect(updated.from == message.from)
		#expect(updated.timestamp == message.timestamp)
		#expect(updated.participant == message.participant)
		#expect(updated.pushName == message.pushName)
		#expect(updated.content == .image(ReceivedImageContent(
			url: "https://mmg.whatsapp.net/v/refreshed-message",
			directPath: "/v/refreshed-message",
			mediaKey: Data((0..<32).map(UInt8.init)),
			fileEncSHA256: Data(repeating: 0x11, count: 32),
			fileSHA256: Data(repeating: 0x22, count: 32),
			fileLength: 128,
			mediaKeyTimestamp: 1_700_000_000,
			mimetype: "image/jpeg",
			caption: "old",
			jpegThumbnail: Data([0xaa])
		)))
		#expect(await events.next() == .messageMediaUpdated([
			MessageMediaUpdate(
				key: WhatsAppMessageKey(
					remoteJID: "123@s.whatsapp.net",
					fromMe: false,
					id: "MEDIA-CLIENT-UPDATE"
				),
				media: try encryptedMediaRetryNotification(messageID: "MEDIA-CLIENT-UPDATE", directPath: "/v/refreshed-message")
			)
		]))
		#expect(await events.next() == .messagesUpdated([
			ReceivedMessageUpdate(
				key: WhatsAppMessageKey(
					remoteJID: "123@s.whatsapp.net",
					fromMe: false,
					id: "MEDIA-CLIENT-UPDATE",
					participant: "456@s.whatsapp.net"
				),
				status: nil,
				timestamp: nil,
				content: updated.content
			)
		]))
	}

	@Test("throws mapped media retry errors while preserving public update events")
	func throwsMappedMediaRetryErrorsWhilePreservingPublicUpdateEvents() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: mediaRetryCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in transport }
		)
		var events = client.events.makeAsyncIterator()
		try await client.connect()
		let request = mediaDownloadRequest(url: URL(string: "https://mmg.whatsapp.net/v/expired")!)
		let key = WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "MEDIA-CLIENT-4")

		let task = Task {
			try await client.updateMediaDownloadRequest(
				request,
				for: key,
				timeout: .seconds(2),
				randomBytes: { count in Data(repeating: 0x09, count: count) }
			)
		}
		_ = try await transport.waitForSentFrame()
		await client.handleIncomingNode(BinaryNode(
			tag: "notification",
			attrs: ["from": "123@s.whatsapp.net", "id": "MEDIA-CLIENT-4", "type": "mediaretry"],
			content: .nodes([
				BinaryNode(tag: "rmr", attrs: ["jid": "123@s.whatsapp.net", "from_me": "false"]),
				BinaryNode(tag: "error", attrs: ["code": "3"])
			])
		))

		await #expect(throws: MediaReuploadRequestError.reuploadError(code: 3, statusCode: 412)) {
			try await task.value
		}
		#expect(await events.next() == .messageMediaUpdated([
			MessageMediaUpdate(
				key: WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "MEDIA-CLIENT-4"),
				errorCode: 3,
				errorStatusCode: 412
			)
		]))
	}

	@Test("downloads expired media after automatic reupload")
	func downloadsExpiredMediaAfterAutomaticReupload() async throws {
		let socketTransport = MockMessageSendWebSocketTransport()
		let encryptedMedia = try MediaEncryption.encrypt(
			Data("swift baileys media fixture".utf8),
			mediaKey: Data((0..<32).map(UInt8.init)),
			mediaType: .image
		)
		let originalURL = URL(string: "https://mmg.whatsapp.net/v/expired")!
		let refreshedURL = URL(string: "https://mmg.whatsapp.net/v/refreshed")!
		let downloadTransport = StubMediaRetryDownloadTransport(results: [
			.failure(URLSessionMediaDownloadTransportError.httpStatus(404, Data("missing".utf8))),
			.success(encryptedMedia.encryptedFile)
		])
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: mediaRetryCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in socketTransport },
			mediaDownloader: WhatsAppMediaDownloader(transport: downloadTransport)
		)
		try await client.connect()
		let request = MediaDownloadRequest(
			url: originalURL,
			mediaKey: Data((0..<32).map(UInt8.init)),
			mediaType: .image,
			fileEncSHA256: encryptedMedia.fileEncSha256,
			fileSHA256: encryptedMedia.fileSha256
		)
		let key = WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "MEDIA-CLIENT-5")

		let task = Task {
			try await client.downloadMedia(
				request,
				updatingExpiredMediaFor: key,
				timeout: .seconds(2),
				randomBytes: { count in Data(repeating: 0x09, count: count) }
			)
		}
		_ = try await socketTransport.waitForSentFrame()
		await client.handleIncomingNode(try mediaRetryNotificationNode(
			messageID: "MEDIA-CLIENT-5",
			result: .success,
			directPath: "/v/refreshed"
		))

		let plaintext = try await task.value
		#expect(plaintext == Data("swift baileys media fixture".utf8))
		#expect(await downloadTransport.urls == [originalURL, refreshedURL])
	}

	@Test("downloads expired received media message after automatic reupload")
	func downloadsExpiredReceivedMediaMessageAfterAutomaticReupload() async throws {
		let socketTransport = MockMessageSendWebSocketTransport()
		let encryptedMedia = try MediaEncryption.encrypt(
			Data("swift baileys media fixture".utf8),
			mediaKey: Data((0..<32).map(UInt8.init)),
			mediaType: .image
		)
		let originalURL = URL(string: "https://mmg.whatsapp.net/v/expired-message")!
		let refreshedURL = URL(string: "https://mmg.whatsapp.net/v/refreshed")!
		let downloadTransport = StubMediaRetryDownloadTransport(results: [
			.failure(URLSessionMediaDownloadTransportError.httpStatus(410, Data("gone".utf8))),
			.success(encryptedMedia.encryptedFile)
		])
		let client = WhatsAppClient(
			authenticationState: AuthenticationState(
				credentials: mediaRetryCredentials(),
				keys: InMemorySignalKeyStore()
			),
			transportFactory: { _ in socketTransport },
			mediaDownloader: WhatsAppMediaDownloader(transport: downloadTransport)
		)
		try await client.connect()
		let message = ReceivedMessage(
			id: "MEDIA-CLIENT-6",
			from: "123@s.whatsapp.net",
			timestamp: nil,
			content: .image(ReceivedImageContent(
				url: originalURL.absoluteString,
				directPath: "/v/expired-message",
				mediaKey: Data((0..<32).map(UInt8.init)),
				fileEncSHA256: encryptedMedia.fileEncSha256,
				fileSHA256: encryptedMedia.fileSha256,
				fileLength: UInt64(encryptedMedia.encryptedFile.count),
				mediaKeyTimestamp: 1_700_000_000,
				mimetype: "image/jpeg",
				caption: nil,
				jpegThumbnail: nil
			)),
			fromMe: false
		)

		let task = Task {
			try await client.downloadMedia(
				from: message,
				updatingExpiredMediaWithTimeout: .seconds(2),
				randomBytes: { count in Data(repeating: 0x09, count: count) }
			)
		}
		_ = try await socketTransport.waitForSentFrame()
		await client.handleIncomingNode(try mediaRetryNotificationNode(
			messageID: "MEDIA-CLIENT-6",
			result: .success,
			directPath: "/v/refreshed"
		))

		let plaintext = try await task.value
		#expect(plaintext == Data("swift baileys media fixture".utf8))
		#expect(await downloadTransport.urls == [originalURL, refreshedURL])
	}
}

private func mediaDownloadRequest(url: URL) -> MediaDownloadRequest {
	MediaDownloadRequest(
		url: url,
		mediaKey: Data((0..<32).map(UInt8.init)),
		mediaType: .image,
		fileEncSHA256: Data(repeating: 0x11, count: 32),
		fileSHA256: Data(repeating: 0x22, count: 32)
	)
}

private func mediaRetryNotificationNode(
	messageID: String,
	result: Proto_MediaRetryNotification.ResultType,
	directPath: String
) throws -> BinaryNode {
	var notification = Proto_MediaRetryNotification()
	notification.stanzaID = messageID
	notification.result = result
	notification.directPath = directPath
	let media = try encryptMediaRetryNotification(notification, mediaKey: Data((0..<32).map(UInt8.init)), messageID: messageID)

	return BinaryNode(
		tag: "notification",
		attrs: ["from": "123@s.whatsapp.net", "id": messageID, "type": "mediaretry"],
		content: .nodes([
			BinaryNode(tag: "rmr", attrs: ["jid": "123@s.whatsapp.net", "from_me": "false"]),
			BinaryNode(tag: "encrypt", content: .nodes([
				BinaryNode(tag: "enc_p", content: .data(media.ciphertext)),
				BinaryNode(tag: "enc_iv", content: .data(media.iv))
			]))
		])
	)
}

private func encryptedMediaRetryNotification(messageID: String, directPath: String) throws -> RetriedMedia {
	var notification = Proto_MediaRetryNotification()
	notification.stanzaID = messageID
	notification.result = .success
	notification.directPath = directPath
	return try encryptMediaRetryNotification(
		notification,
		mediaKey: Data((0..<32).map(UInt8.init)),
		messageID: messageID
	)
}

private func encryptMediaRetryNotification(
	_ notification: Proto_MediaRetryNotification,
	mediaKey: Data,
	messageID: String
) throws -> RetriedMedia {
	let retryKey = HKDF<SHA256>.deriveKey(
		inputKeyMaterial: SymmetricKey(data: mediaKey),
		salt: Data(),
		info: Data("WhatsApp Media Retry Notification".utf8),
		outputByteCount: 32
	)
	let iv = Data((0..<12).map(UInt8.init))
	let box = try AES.GCM.seal(
		try notification.serializedData(),
		using: retryKey,
		nonce: AES.GCM.Nonce(data: iv),
		authenticating: Data(messageID.utf8)
	)
	return RetriedMedia(ciphertext: box.ciphertext + box.tag, iv: iv)
}

private func mediaRetryCredentials() -> AuthenticationCredentials {
	AuthenticationCredentials(
		noiseKey: AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data(repeating: 2, count: 32)),
		pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data(repeating: 3, count: 32), publicKey: Data(repeating: 4, count: 32)),
		signedIdentityKey: AuthenticationKeyPair(privateKey: Data(repeating: 5, count: 32), publicKey: Data(repeating: 6, count: 32)),
		signedPreKey: SignedAuthenticationKeyPair(
			keyPair: AuthenticationKeyPair(privateKey: Data(repeating: 7, count: 32), publicKey: Data(repeating: 8, count: 32)),
			signature: Data(repeating: 9, count: 64),
			keyID: 1
		),
		registrationID: 1,
		advSecretKey: "adv-secret",
		me: WhatsAppUser(id: "258840000100:3@s.whatsapp.net", name: "Swift"),
		nextPreKeyID: 1,
		firstUnuploadedPreKeyID: 1,
		accountSyncCounter: 0,
		registered: true
	)
}

private actor StubMediaRetryDownloadTransport: MediaDownloading {
	private var results: [Result<Data, any Error>]
	private(set) var urls: [URL] = []

	init(results: [Result<Data, any Error>]) {
		self.results = results
	}

	func download(from url: URL) async throws -> Data {
		urls.append(url)
		let result = results.isEmpty ? .success(Data()) : results.removeFirst()
		return try result.get()
	}
}
