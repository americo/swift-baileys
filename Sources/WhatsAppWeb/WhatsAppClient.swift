import Foundation

public struct WhatsAppClientConfiguration: Sendable {
	public var connectTimeout: Duration
	public var companionPlatformID: String
	public var maxMessageRetryCount: Int
	public var webSocketURL: URL
	public var historySyncPausedTimeout: Duration
	public var shouldIgnoreJID: @Sendable (String) -> Bool?
	/// WhatsApp Web version sent at login. `nil` resolves the latest published version at connect time.
	public var version: WhatsAppVersion?

	public init(
		connectTimeout: Duration = .seconds(20),
		companionPlatformID: String = WhatsAppBrowserPlatform.companionPlatformID(for: .macOS("Desktop")),
		maxMessageRetryCount: Int = 5,
		webSocketURL: URL = URL(string: "wss://web.whatsapp.com/ws/chat")!,
		historySyncPausedTimeout: Duration = .seconds(120),
		shouldIgnoreJID: @escaping @Sendable (String) -> Bool? = { _ in false },
		version: WhatsAppVersion? = nil
	) {
		self.connectTimeout = connectTimeout
		self.companionPlatformID = companionPlatformID
		self.maxMessageRetryCount = maxMessageRetryCount
		self.webSocketURL = webSocketURL
		self.historySyncPausedTimeout = historySyncPausedTimeout
		self.shouldIgnoreJID = shouldIgnoreJID
		self.version = version
	}
}

public enum WhatsAppClientState: Equatable, Sendable {
	case disconnected
	case connecting
	case connected
}

public enum WhatsAppClientEvent: Equatable, Sendable {
	case qrCode(String)
	case connected(user: String)
	case disconnected(reason: String)
	case message(BinaryNode)
	case receivedMessage(ReceivedMessage)
	case messagingHistorySet(MessagingHistorySet)
	case messagingHistoryStatus(MessagingHistoryStatusUpdate)
	case messageDecryptionFailed(MessageDecryptionFailure)
	case messageRetryResendFailed(MessageRetryResendFailure)
	case presenceUpdated(WhatsAppPresenceUpdate)
	case call([WhatsAppCallEvent])
	case appStateSyncRequested(AppStateSyncRequest)
	case chatsUpdated([ChatUpdate])
	case contactsUpdated([ContactUpdate])
	case lidMappingUpdated(LIDMapping)
	case blocklistUpdated(BlocklistUpdate)
	case messagesUpdated([ReceivedMessageUpdate])
	case messagesDeleted(MessageDeleteUpdate)
	case chatsDeleted(ChatDeleteUpdate)
	case chatLockUpdated(ChatLockUpdate)
	case messageReactionsUpdated([ReceivedMessageReactionUpdate])
	case messagePollUpdates([ReceivedMessagePollUpdate])
	case messageEventResponsesUpdated([ReceivedMessageEventResponseUpdate])
	case messageMediaUpdated([MessageMediaUpdate])
	case deviceListUpdated([DeviceListUpdate])
	case preKeyCountUpdated(PreKeyCountUpdate)
	case preKeyUploadFailed(PreKeyUploadFailure)
	case identityChanged(IdentityChangeUpdate)
	case groupMemberLabelUpdated(GroupMemberLabelUpdate)
	case labelEdited(LabelUpdate)
	case labelAssociationUpdated(LabelAssociationUpdate)
	case settingsUpdated(SettingsUpdate)
	case favoriteStickerUpdated(FavoriteStickerUpdate)
	case newsletterReactionUpdated(NewsletterReactionUpdate)
	case newsletterViewUpdated(NewsletterViewUpdate)
	case newsletterParticipantsUpdated(NewsletterParticipantUpdate)
	case newsletterSettingsUpdated(NewsletterSettingsUpdate)
	case reachoutTimelockUpdated(ReachoutTimelockUpdate)
	case messageCappingUpdated(MessageCappingUpdate)
	case messageReceiptsUpdated([ReceivedMessageReceiptUpdate])
	case messageRetryRequested(MessageRetryRequest)
	case credentialsUpdated(AuthenticationCredentials)
	case newLogin
}

public actor WhatsAppClient {
	public let configuration: WhatsAppClientConfiguration
	public nonisolated let events: AsyncStream<WhatsAppClientEvent>
	public private(set) var state: WhatsAppClientState = .disconnected
	public private(set) var authenticationState: AuthenticationState?
	private nonisolated let localSignalIdentity: CurrentLocalSignalIdentity

	let eventContinuation: AsyncStream<WhatsAppClientEvent>.Continuation
	private let pairSuccessProcessor: (any PairSuccessProcessing)?
	let mediaUpdateCoordinator = MediaUpdateCoordinator()
	var messageEncryptor: (any MessageEncrypting)?
	var groupMessageEncryptor: (any GroupMessageEncrypting)?
	var messageDecryptor: (any IncomingMessageDecrypting)?
	var messageDeviceResolver: (any MessageDeviceResolving)?
	var signalSessionPreparer: (any SignalSessionPreparing)?
	var retrySessionInjector: (any SignalSessionInjecting)?
	var signedPreKeySigner: (any SignalSignedPreKeySigning)?
	var eventResponseContextResolver: (any EventResponseContextResolving)?
	var pollVoteContextResolver: (any PollVoteContextResolving)?
	var messageSecretResolver: (any MessageSecretResolving)?
	var linkPreviewResolver: (any LinkPreviewResolving)?
	var mediaUploader: (any WhatsAppMediaUploading)?
	let mediaDownloader: WhatsAppMediaDownloader
	let mediaKeyGenerator: any MediaKeyGenerating
	let mediaKeyTimestamp: @Sendable () -> Int64
	var preKeyUploader: (any PreKeyUploading)?
	let preKeyGenerator: @Sendable () throws -> AuthenticationKeyPair
	let linkCodeCompanionRegistrationProcessor: (any LinkCodeCompanionRegistrationProcessing)?
	let messageEncoder: MessageEncoder
	let messageIDGenerator: MessageIDGenerator
	private let transportFactory: @Sendable (URL) -> any WhatsAppWebSocketTransport
	let requestCoordinator = IQRequestCoordinator()
	private var transport: (any WhatsAppWebSocketTransport)?
	private var receiveTask: Task<Void, Never>?
	/// Last frame handed to the socket. See `sendInOrder`.
	private var lastOutboundFrame: Task<Void, Error>?
	var outboundFrameCodec = NoiseFrameCodec()
	var noiseTransport: NoiseTransportState?
	var keepAliveTask: Task<Void, Never>?
	var callOfferCache: [String: WhatsAppCallEvent] = [:]
	/// Raw `<call>` stanzas of offers still ringing, kept so the call key can be decrypted on accept.
	var callOfferNodes: [String: BinaryNode] = [:]
	/// Rosters and media keys of group calls, ahead of whichever media session ends up using them.
	var groupCalls: [String: GroupCallRecord] = [:]
	var recentSentMessages: [RecentSentMessageKey: RecentSentMessage] = [:]
	var recentSentMessageOrder: [RecentSentMessageKey] = []
	var retryResendCounts: [RetryResendKey: Int] = [:]
	var preKeyUploadTask: Task<Void, Error>?
	var serverProps = WhatsAppServerProps()
	var inFlightTrustedContactTokenIssues: Set<String> = []
	var blockedAppStateSyncCollections: Set<AppStateCollectionName> = []
	var appStateWorkTail: Task<Void, Never>?
	var appStateKeyExpander: (any AppStateKeyExpanding)?
	var appStateHashMixer: (any AppStatePatchHashMixing)?
	var appStateRandomBytes: (@Sendable (Int) throws -> Data)?
	public internal(set) var serverTimeOffsetMilliseconds: Int64 = 0
	var initialBootstrapHistoryComplete = false
	var recentHistoryComplete = false
	var recentHistoryPausedTask: Task<Void, Never>?
	public internal(set) var wamBuffer = WAMBinaryInfo()

	public init(
		configuration: WhatsAppClientConfiguration = WhatsAppClientConfiguration(),
		authenticationState: AuthenticationState? = nil,
		pairSuccessProcessor: (any PairSuccessProcessing)? = nil,
		transportFactory: @escaping @Sendable (URL) -> any WhatsAppWebSocketTransport = {
			URLSessionWebSocketTransport(url: $0)
		}
	) {
		self.init(
			configuration: configuration,
			authenticationState: authenticationState,
			pairSuccessProcessor: pairSuccessProcessor,
			transportFactory: transportFactory,
			messageEncryptor: nil,
			groupMessageEncryptor: nil,
			messageDecryptor: nil,
			messageDeviceResolver: nil,
			signalSessionPreparer: nil,
			retrySessionInjector: nil,
			messageEncoder: MessageEncoder(),
			messageIDGenerator: MessageIDGenerator(),
			mediaUploader: nil,
			mediaDownloader: WhatsAppMediaDownloader(transport: URLSessionMediaDownloadTransport()),
			mediaKeyGenerator: SecureMediaKeyGenerator(),
			mediaKeyTimestamp: { Int64(Date().timeIntervalSince1970) },
			preKeyUploader: nil,
			preKeyGenerator: AuthenticationCredentialsFactory.makeCurve25519KeyPair,
			linkCodeCompanionRegistrationProcessor: DefaultLinkCodeCompanionRegistrationProcessor()
		)
	}

	public init(
		configuration: WhatsAppClientConfiguration = WhatsAppClientConfiguration(),
		authenticationState: AuthenticationState? = nil,
		pairSuccessProcessor: (any PairSuccessProcessing)? = nil,
		messageDependencies: WhatsAppClientMessageDependencies,
		transportFactory: @escaping @Sendable (URL) -> any WhatsAppWebSocketTransport = {
			URLSessionWebSocketTransport(url: $0)
		}
	) {
		let localSignalIdentity = CurrentLocalSignalIdentity(jid: authenticationState?.credentials.me?.id)
		self.init(
			configuration: configuration,
			authenticationState: authenticationState,
			pairSuccessProcessor: pairSuccessProcessor,
			transportFactory: transportFactory,
			messageEncryptor: messageDependencies.messageEncryptor,
			groupMessageEncryptor: messageDependencies.groupMessageEncryptor,
			messageDecryptor: messageDependencies.incomingSignalDecryptor.map {
				Self.makeIncomingMessageDecryptor(
					signalDecryptor: $0,
					localSignalIdentity: localSignalIdentity,
					keys: authenticationState?.keys
				)
			},
			messageDeviceResolver: messageDependencies.messageDeviceResolver,
			signalSessionPreparer: messageDependencies.signalSessionPreparer,
			retrySessionInjector: messageDependencies.retrySessionInjector,
			messageEncoder: MessageEncoder(),
			messageIDGenerator: MessageIDGenerator(),
			mediaUploader: messageDependencies.mediaUploader,
			mediaDownloader: WhatsAppMediaDownloader(transport: URLSessionMediaDownloadTransport()),
			mediaKeyGenerator: SecureMediaKeyGenerator(),
			mediaKeyTimestamp: { Int64(Date().timeIntervalSince1970) },
			preKeyUploader: messageDependencies.preKeyUploader,
			preKeyGenerator: AuthenticationCredentialsFactory.makeCurve25519KeyPair,
			linkCodeCompanionRegistrationProcessor: DefaultLinkCodeCompanionRegistrationProcessor(),
			localSignalIdentity: localSignalIdentity
		)
	}

	init(
		configuration: WhatsAppClientConfiguration = WhatsAppClientConfiguration(),
		authenticationState: AuthenticationState? = nil,
		pairSuccessProcessor: (any PairSuccessProcessing)? = nil,
		transportFactory: @escaping @Sendable (URL) -> any WhatsAppWebSocketTransport = {
			URLSessionWebSocketTransport(url: $0)
		},
		messageEncryptor: (any MessageEncrypting)? = nil,
		groupMessageEncryptor: (any GroupMessageEncrypting)? = nil,
		messageDecryptor: (any IncomingMessageDecrypting)? = nil,
		messageDeviceResolver: (any MessageDeviceResolving)? = nil,
		signalSessionPreparer: (any SignalSessionPreparing)? = nil,
		retrySessionInjector: (any SignalSessionInjecting)? = nil,
		messageEncoder: MessageEncoder = MessageEncoder(),
		messageIDGenerator: MessageIDGenerator = MessageIDGenerator(),
		mediaUploader: (any WhatsAppMediaUploading)? = nil,
		mediaDownloader: WhatsAppMediaDownloader = WhatsAppMediaDownloader(
			transport: URLSessionMediaDownloadTransport()
		),
		mediaKeyGenerator: any MediaKeyGenerating = SecureMediaKeyGenerator(),
		mediaKeyTimestamp: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970) },
		preKeyUploader: (any PreKeyUploading)? = nil,
		preKeyGenerator: @escaping @Sendable () throws -> AuthenticationKeyPair =
			AuthenticationCredentialsFactory.makeCurve25519KeyPair,
		linkCodeCompanionRegistrationProcessor: (any LinkCodeCompanionRegistrationProcessing)? =
			DefaultLinkCodeCompanionRegistrationProcessor(),
		localSignalIdentity: CurrentLocalSignalIdentity = CurrentLocalSignalIdentity()
	) {
		self.configuration = configuration
		self.authenticationState = authenticationState
		self.localSignalIdentity = localSignalIdentity
		self.localSignalIdentity.update(authenticationState?.credentials.me?.id)
		self.pairSuccessProcessor = pairSuccessProcessor
		self.messageEncryptor = messageEncryptor
		self.groupMessageEncryptor = groupMessageEncryptor
		self.messageDecryptor = messageDecryptor
		self.messageDeviceResolver = messageDeviceResolver
		self.signalSessionPreparer = signalSessionPreparer
		self.retrySessionInjector = retrySessionInjector
		self.mediaUploader = mediaUploader
		self.mediaKeyGenerator = mediaKeyGenerator
		self.mediaKeyTimestamp = mediaKeyTimestamp
		self.messageEncoder = messageEncoder
		self.messageIDGenerator = messageIDGenerator
		self.mediaDownloader = mediaDownloader
		self.transportFactory = transportFactory
		self.preKeyUploader = preKeyUploader
		self.preKeyGenerator = preKeyGenerator
		self.linkCodeCompanionRegistrationProcessor = linkCodeCompanionRegistrationProcessor
		let stream = AsyncStream<WhatsAppClientEvent>.makeStream()
		self.events = stream.stream
		self.eventContinuation = stream.continuation
	}

	deinit {
		recentHistoryPausedTask?.cancel()
		eventContinuation.finish()
	}

	public func connect() async throws {
		state = .connecting
		let nextTransport = transportFactory(configuration.webSocketURL)
		do {
			try await nextTransport.connect()
		} catch {
			await nextTransport.close()
			state = .disconnected
			throw error
		}
		guard let credentials = authenticationState?.credentials else {
			await nextTransport.close()
			state = .disconnected
			throw WhatsAppClientError.missingAuthenticationState
		}
		let version: WhatsAppVersion
		if let configured = configuration.version {
			version = configured
		} else {
			version = await WhatsAppVersionResolver.fetchLatestWaWebVersion().version
		}
		let inboundCodec: NoiseFrameCodec
		do {
			let handshake = try await performNoiseHandshake(over: nextTransport, credentials: credentials, version: version)
			noiseTransport = handshake.0
			inboundCodec = handshake.1
		} catch {
			await nextTransport.close()
			noiseTransport = nil
			state = .disconnected
			throw error
		}
		transport = nextTransport
		state = .connected
		await pruneExpiredTrustedContactTokens()
		startReceiveLoop(transport: nextTransport, codec: inboundCodec)
	}

	/// Encrypts (once the Noise handshake is done) and length-prefixes an outbound payload.
	func encodeOutboundFrame(_ payload: Data) throws -> Data {
		var data = payload
		if noiseTransport != nil {
			data = try noiseTransport!.encrypt(payload)
		}
		return outboundFrameCodec.encode(data)
	}

	func decryptInboundFrame(_ frame: Data) throws -> Data {
		guard noiseTransport != nil else { return frame }
		return try noiseTransport!.decrypt(frame)
	}

	public func configureMessageDependencies(_ dependencies: WhatsAppClientMessageDependencies) {
		messageEncryptor = dependencies.messageEncryptor
		groupMessageEncryptor = dependencies.groupMessageEncryptor
		messageDeviceResolver = dependencies.messageDeviceResolver
		signalSessionPreparer = dependencies.signalSessionPreparer
		retrySessionInjector = dependencies.retrySessionInjector
		mediaUploader = dependencies.mediaUploader
		preKeyUploader = dependencies.preKeyUploader
		messageDecryptor = dependencies.incomingSignalDecryptor.map {
			Self.makeIncomingMessageDecryptor(
				signalDecryptor: $0,
				localSignalIdentity: localSignalIdentity,
				keys: authenticationState?.keys
			)
		}
	}

	public func configureAppStateDependencies(
		keyExpander: any AppStateKeyExpanding,
		hashMixer: any AppStatePatchHashMixing,
		randomBytes: (@Sendable (Int) throws -> Data)? = nil
	) {
		appStateKeyExpander = keyExpander
		appStateHashMixer = hashMixer
		appStateRandomBytes = randomBytes
	}

	public func configureNativeSignalAdapter(
		_ nativeSignalAdapter: any WhatsAppNativeSignalAdapter,
		query: WhatsAppClientMessageDependencies.Query? = nil,
		mediaUploader: (any WhatsAppMediaUploading)? = nil
	) {
		signedPreKeySigner = nativeSignalAdapter
		let resolvedQuery: WhatsAppClientMessageDependencies.Query = query ?? { [weak self] node, timeout in
			guard let self else {
				throw WhatsAppClientError.notConnected
			}

			return try await self.query(node, timeout: timeout)
		}
		configureMessageDependencies(WhatsAppClientMessageDependencies(
			nativeSignalAdapter: nativeSignalAdapter,
			query: resolvedQuery,
			mediaUploader: mediaUploader,
			localJIDProvider: { [localSignalIdentity] in
				localSignalIdentity.jid
			}
		))
	}

	public func sendRawFrame(_ data: Data) async throws {
		guard let transport else {
			throw WhatsAppClientError.notConnected
		}

		try await sendInOrder(data, through: transport)
	}

	/// Encrypts and sends as one step, so a frame's Noise counter matches its position on the wire.
	private func encryptAndSend(_ payload: Data, through transport: any WhatsAppWebSocketTransport) async throws {
		try await sendInOrder(encodeOutboundFrame(payload), through: transport)
	}

	/// Frames are numbered when encrypted and the server rejects any that arrive out of order
	/// (`bad-mac`). Concurrent callers would otherwise race to the socket once they leave the actor.
	private func sendInOrder(_ frame: Data, through transport: any WhatsAppWebSocketTransport) async throws {
		let previous = lastOutboundFrame
		let sending = Task {
			_ = await previous?.result
			try await transport.send(frame)
		}
		lastOutboundFrame = sending
		try await sending.value
	}

	public func query(_ node: BinaryNode, timeout: Duration = .seconds(60)) async throws -> BinaryNode {
		guard let id = node.attrs["id"] else {
			throw WhatsAppClientError.missingRequestID
		}
		guard !id.isEmpty else {
			throw WhatsAppClientError.emptyRequestID
		}

		guard let transport else {
			throw WhatsAppClientError.notConnected
		}

		let payload = try BinaryNodeEncoder().encode(node)
		WhatsAppLog.logger.notice("query -> \(node.tag, privacy: .public) xmlns=\(node.attrs["xmlns"] ?? "-", privacy: .public) type=\(node.attrs["type"] ?? "-", privacy: .public) id=\(id, privacy: .public) bytes=\(payload.count)")

		let response: BinaryNode
		do {
			response = try await requestCoordinator.perform(id: id, timeout: timeout) {
				try await self.encryptAndSend(payload, through: transport)
			}
		} catch {
			WhatsAppLog.logger.error("query failed id=\(id, privacy: .public) xmlns=\(node.attrs["xmlns"] ?? "-", privacy: .public): \(String(describing: error), privacy: .public)")
			throw error
		}
		WhatsAppLog.logger.notice("query <- id=\(id, privacy: .public) type=\(response.attrs["type"] ?? "-", privacy: .public)")
		try response.assertServerErrorFree()
		return response
	}

	public func handleIncomingNode(_ node: BinaryNode) async {
		if node.tag == "iq" || node.tag == "ib" || node.tag == "failure" || node.tag == "stream:error" || (node.tag == "ack" && node.attrs["class"] == "message") {
			let child: String
			if case .nodes(let children)? = node.content { child = children.map(\.tag).joined(separator: ",") } else { child = "-" }
			WhatsAppLog.logger.notice("node \(node.tag, privacy: .public) type=\(node.attrs["type"] ?? "-", privacy: .public) xmlns=\(node.attrs["xmlns"] ?? "-", privacy: .public) id=\(node.attrs["id"] ?? "-", privacy: .public) error=\(node.attrs["error"] ?? "-", privacy: .public) children=\(child, privacy: .public)")
		}
		if await handleConnectionTerminationNode(node) {
			return
		}

		if await handleLoginSuccessNode(node) {
			return
		}

		if await handlePairDeviceNode(node) {
			return
		}

		if await handlePairSuccessNode(node) {
			return
		}

		let resolved = await requestCoordinator.resolve(node)
		if !resolved {
			if await handleReceiptNode(node) {
				return
			}

			if await handleMessageAckNode(node) {
				return
			}

			if await handleNotificationNode(node) {
				return
			}

			if await handleOfflineNode(node) {
				return
			}

			if await handleDirtyBitsNode(node) {
				return
			}

			if await handlePresenceNode(node) {
				return
			}

			if await handleCallNode(node) {
				return
			}

			if await handleReceivedMessageNode(node) {
				return
			}

			eventContinuation.yield(.message(node))
		}
	}

	public func updateCredentials(_ update: @Sendable (inout AuthenticationCredentials) throws -> Void) async throws {
		guard var authenticationState else {
			throw WhatsAppClientError.missingAuthenticationState
		}

		try await authenticationState.updateCredentials(update)
		self.authenticationState = authenticationState
		localSignalIdentity.update(authenticationState.credentials.me?.id)
		eventContinuation.yield(.credentialsUpdated(authenticationState.credentials))
	}

	public func logout(reason: String = "Intentional Logout", requestID: String? = nil) async throws {
		if let jid = authenticationState?.credentials.me?.id {
			let id = try requestID ?? messageIDGenerator.generateV2(userID: jid)
			try await sendNode(BinaryNode(
				tag: "iq",
				attrs: [
					"id": id,
					"xmlns": "md",
					"to": "@s.whatsapp.net",
					"type": "set"
				],
				content: .nodes([
					BinaryNode(
						tag: "remove-companion-device",
						attrs: ["jid": jid, "reason": "user_initiated"]
					)
				])
			))
		}

		await disconnect(reason: reason)
	}

	public func disconnect(reason: String) async {
		receiveTask?.cancel()
		receiveTask = nil
		recentHistoryPausedTask?.cancel()
		recentHistoryPausedTask = nil
		await requestCoordinator.failAll(error: WhatsAppClientError.disconnected(reason: reason))
		await mediaUpdateCoordinator.failAll(error: WhatsAppClientError.disconnected(reason: reason))
		keepAliveTask?.cancel()
		keepAliveTask = nil
		noiseTransport = nil
		await transport?.close()
		transport = nil
		state = .disconnected
		eventContinuation.yield(.disconnected(reason: reason))
	}

	/// Runs on a transport without the handshake, which needs real credentials. For tests.
	func attach(transport: any WhatsAppWebSocketTransport) {
		self.transport = transport
		state = .connected
		startReceiveLoop(transport: transport, codec: NoiseFrameCodec())
	}

	private func startReceiveLoop(transport: any WhatsAppWebSocketTransport, codec initialCodec: NoiseFrameCodec) {
		receiveTask?.cancel()
		lastOutboundFrame = nil
		// Handlers may query the server (prekey uploads, retries), and only this loop can read the
		// reply. Replies are delivered here; everything else runs in order on a separate task, or a
		// handler that queries would block the loop until its own request timed out.
		let (nodes, nodeQueue) = AsyncStream.makeStream(of: BinaryNode.self)
		Task {
			for await node in nodes {
				await handleIncomingNode(node)
			}
		}
		receiveTask = Task {
			defer { nodeQueue.finish() }
			var codec = initialCodec
			let decoder = BinaryNodeDecoder()

			while !Task.isCancelled {
				do {
					guard let data = try await transport.receive() else {
						await finishReceiveLoop(reason: "Connection Closed")
						return
					}

					for frame in codec.decode(data) {
						let plain = try await self.decryptInboundFrame(frame)
						let node = try decoder.decode(plain)
						if await requestCoordinator.isAwaiting(node) {
							await handleIncomingNode(node)
						} else {
							nodeQueue.yield(node)
						}
					}
				} catch {
					await finishReceiveLoop(reason: "Receive Loop Error (\(error))")
					return
				}
			}
		}
	}

	private func finishReceiveLoop(reason: String) async {
		guard state != .disconnected else {
			return
		}

		receiveTask = nil
		recentHistoryPausedTask?.cancel()
		recentHistoryPausedTask = nil
		await requestCoordinator.failAll(error: WhatsAppClientError.disconnected(reason: reason))
		await mediaUpdateCoordinator.failAll(error: WhatsAppClientError.disconnected(reason: reason))
		keepAliveTask?.cancel()
		keepAliveTask = nil
		noiseTransport = nil
		await transport?.close()
		transport = nil
		state = .disconnected
		eventContinuation.yield(.disconnected(reason: reason))
	}

	public func sendNode(_ node: BinaryNode) async throws {
		guard let transport else {
			throw WhatsAppClientError.notConnected
		}

		var node = node
		if node.tag == "message" {
			node = withDeviceIdentityIfNeeded(node)
			WhatsAppLog.logger.notice("stanza \(Self.describe(node), privacy: .public)")
			WhatsAppLog.logger.notice("send message id=\(node.attrs["id"] ?? "-", privacy: .public) to=\(node.attrs["to"] ?? "-", privacy: .public) enc=\(Self.encTypes(in: node).joined(separator: ","), privacy: .public) identity=\(node.firstChild(named: "device-identity") != nil)")
		}
		let payload = try BinaryNodeEncoder().encode(node)
		try await encryptAndSend(payload, through: transport)
	}

	/// A message that opens a Signal session (`pkmsg`) must carry the account's signed device identity,
	/// otherwise the recipient cannot verify the new session and the server drops the message.
	private func withDeviceIdentityIfNeeded(_ node: BinaryNode) -> BinaryNode {
		guard Self.encTypes(in: node).contains("pkmsg"),
			  node.firstChild(named: "device-identity") == nil,
			  let account = authenticationState?.credentials.account,
			  let identity = try? Self.encodedSignedDeviceIdentity(account),
			  case .nodes(let children)? = node.content else {
			return node
		}
		return BinaryNode(
			tag: node.tag,
			attrs: node.attrs,
			content: .nodes(children + [BinaryNode(tag: "device-identity", content: .data(identity))])
		)
	}

	/// Structure of a node without payload bytes, for diagnosing rejected stanzas.
	private static func describe(_ node: BinaryNode) -> String {
		let attrs = node.attrs.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
		switch node.content {
		case .nodes(let children)?:
			return "<\(node.tag) \(attrs)>" + children.map(describe).joined() + "</\(node.tag)>"
		case .data(let data)?:
			return "<\(node.tag) \(attrs) bytes=\(data.count)/>"
		case .string(let text)?:
			return "<\(node.tag) \(attrs)>\(text)</\(node.tag)>"
		case nil:
			return "<\(node.tag) \(attrs)/>"
		}
	}

	private static func encTypes(in node: BinaryNode) -> [String] {
		guard case .nodes(let children)? = node.content else { return [] }
		return children.flatMap { child -> [String] in
			if child.tag == "enc" { return [child.attrs["type"] ?? "?"] }
			return encTypes(in: child)
		}
	}

	private func handleConnectionTerminationNode(_ node: BinaryNode) async -> Bool {
		switch node.tag {
		case "stream:error":
			await disconnect(reason: "Stream Errored (\(ConnectionErrorMapper.streamErrorInfo(from: node).reason))")
			return true
		case "failure":
			await disconnect(reason: "Connection Failure (\(node.attrs["reason"] ?? "500"))")
			return true
		case "xmlstreamend":
			await disconnect(reason: "Connection Terminated by Server")
			return true
		default:
			return false
		}
	}

	private func handlePairDeviceNode(_ node: BinaryNode) async -> Bool {
		guard node.tag == "iq", node.attrs["type"] == "set",
			  let credentials = authenticationState?.credentials,
			  let pairDevice = node.firstChild(named: "pair-device"),
			  let ref = pairDevice.childString(named: "ref") else {
			return false
		}

		if let id = node.attrs["id"] {
			try? await sendNode(
				BinaryNode(
					tag: "iq",
					attrs: ["to": "@s.whatsapp.net", "type": "result", "id": id]
				)
			)
		}

		eventContinuation.yield(
			.qrCode(
				PairingQRCode.build(
					ref: ref,
					credentials: credentials,
					platformID: configuration.companionPlatformID
				)
			)
		)
		return true
	}

	private func handlePairSuccessNode(_ node: BinaryNode) async -> Bool {
		guard node.tag == "iq", node.firstChild(named: "pair-success") != nil,
			  let pairSuccessProcessor,
			  var authenticationState else {
			return false
		}

		do {
			let result = try pairSuccessProcessor.processPairSuccess(
				stanza: node,
				credentials: authenticationState.credentials
			)
			try await authenticationState.updateCredentials { credentials in
				try result.apply(to: &credentials)
			}
			self.authenticationState = authenticationState
			localSignalIdentity.update(authenticationState.credentials.me?.id)
			eventContinuation.yield(.credentialsUpdated(authenticationState.credentials))
			eventContinuation.yield(.newLogin)
			try await sendNode(result.reply)
			return true
		} catch {
			return false
		}
	}

}

public enum WhatsAppClientError: Error, Equatable, Sendable {
	case notConnected
	case missingRequestID
	case emptyRequestID
	case missingAuthenticationState
	case missingMessageEncryptor
	case missingGroupMessageEncryptor
	case missingMessageDeviceResolver
	case missingSignalSessionPreparer
	case missingSignedPreKeySigner
	case missingMediaUploader
	case missingAuthenticatedUser
	case missingMessageDestination
	case missingRecipientJID
	case missingReceiptMessageIDs
	case missingRetryMessage
	case missingRetryTimestamp
	case missingBusinessProductResponse
	case missingBusinessCoverPhotoUploadResponse
	case missingAppStateKeyID
	case invalidAppStateKeyID
	case missingAppStateSyncKey
	case appStatePatchRejected(collection: String, code: String?)
	case invalidBlocklistJID(String)
	case missingLIDMappingForPN(String)
	case missingPNMappingForLID(String)
	case disconnected(reason: String)
}
