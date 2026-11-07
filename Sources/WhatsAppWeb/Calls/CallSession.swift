import Foundation

/// A datagram path to the call relay. `CallRelayTransport` is the real one; tests use a fake.
public protocol CallRelayLink: Sendable {
	/// Messages received from the relay: STUN, RTP and RTCP, one per element.
	var messages: AsyncStream<Data> { get }
	func open() async throws
	func send(_ message: Data) async throws
	func close() async
	/// How the path toward the relay is coping since the last time this was read. It answers from this
	/// side alone, so it still speaks when the congestion has stopped the peer's reports from arriving.
	func sendPressure() async -> SCTPAssociation.SendPressure?
}

extension CallRelayLink {
	public func sendPressure() async -> SCTPAssociation.SendPressure? {
		nil
	}
}

extension CallRelayTransport: CallRelayLink {
	public func open() async throws {
		try await connect()
	}
}

public enum CallSessionError: Error, Equatable, Sendable {
	case noRelay
	case missingRelayToken
	case missingIntegrityKey
	case allocateRejected(Int?)
	case allocateTimedOut
	case notRunning
}

/// What the session needs from whoever owns the encoder.
public enum CallVideoSendEvent: Equatable, Sendable {
	/// The next picture must be an IDR: the peer asked for one, or nothing else may go out until one does.
	case keyframeNeeded
	/// How the peer's loss reports say the encoder should run, in bit/s.
	case targetBitrate(Int)
}

/// Media half of a call: registers with the relay (STUN Allocate and keepalives), then turns
/// microphone frames into protected Opus RTP and encoded pictures into protected H.264 RTP, and
/// incoming RTP back into PCM and pictures.
///
/// Every call can carry video, since a voice call can be upgraded. Signaling is separate
/// (`startVoiceCall`, `acceptVoiceCall`); this takes the call key and relay block those produce.
///
/// A group call is the same session with participant-indexed receiving on top. It starts that way, or
/// becomes it when a 1:1 call's first roster arrives. Sending is shared: one stream, keyed per epoch.
public actor CallSession {
	public struct Configuration: Sendable {
		public let callID: String
		public let selfParticipantID: String
		public let peerParticipantID: String
		public let callKey: Data
		public let relay: CallRelayData
		/// The first roster of a call that starts as a group call. Media waits for its first key.
		public let groupUpdate: GroupCallUpdate?

		public init(
			callID: String,
			selfParticipantID: String,
			peerParticipantID: String,
			callKey: Data,
			relay: CallRelayData,
			groupUpdate: GroupCallUpdate? = nil
		) {
			self.callID = callID
			self.selfParticipantID = selfParticipantID
			self.peerParticipantID = peerParticipantID
			self.callKey = callKey
			self.relay = relay
			self.groupUpdate = groupUpdate
		}
	}

	public static let allocateRetryInterval: Duration = .seconds(1)
	public static let allocateTimeout: Duration = .seconds(10)
	/// The Allocate is re-sent with a fresh ping at this cadence for the whole call: the relay takes
	/// it as consent to keep forwarding.
	public static let keepaliveInterval: Duration = .seconds(1)
	/// How long the peer can send nothing at all before the call is taken to be over. Official clients
	/// send RTCP every 1.5 s even while muted, so silence this long means a dead path or a peer that has
	/// gone. A congested link has been seen to hold everything back for over 10 s with the peer still in
	/// the call, and its hang-up on the way, so the wait is long enough to outlast that.
	public static let defaultPeerSilenceTimeout: Duration = .seconds(30)
	/// Cadence of the reports each side sends about the video it receives and sends.
	public static let reportInterval: Duration = .milliseconds(1500)
	/// How long the peer's keyframe is waited on before asking again.
	public static let peerKeyframeInterval: Duration = .seconds(1)
	/// Floor under an urgent request, such as a decoder that has just failed on every picture.
	public static let urgentPeerKeyframeInterval: Duration = .milliseconds(200)
	/// Where the encoder starts, and what the path may move it between. Without a measure of the path,
	/// starting low costs a softer picture for a few seconds, and starting too high has stalled whole
	/// calls on a link that could not carry it, signaling included.
	public static let initialVideoBitrate = 700_000
	public static let minimumVideoBitrate = 250_000
	public static let maximumVideoBitrate = 2_000_000
	/// One stream goes to everyone in a group, so the path of the slowest sets the worth of a higher rate.
	public static let maximumGroupVideoBitrate = 1_000_000
	/// Reactions being repeated at once. Anyone faster than this loses the repeats of the oldest.
	static let maxReactionResends = 64
	/// Playout cadence of a group call, where the mixer is what produces audio.
	public static let groupPlayoutInterval: Duration = .milliseconds(20)

	/// How far above the measured video rate the pacer runs, the factor WebRTC's paced sender uses.
	private static let paceFactor = 2.5
	/// The pace before the call has a rate to go by, and the least it ever runs at.
	private static let paceFloorBps: Double = 4_000_000
	/// How much may leave at once: an ordinary frame goes through whole, while a keyframe is spread out.
	private static let paceBurst: Duration = .milliseconds(40)
	private static let paceWindow: Duration = .seconds(1)
	/// Sent packets kept to answer NACKs, longer than a NACK takes to come back over any path.
	private static let sentHistorySize = 512
	/// Backed off for this long after congestion, however clean the peer's reports look: they describe
	/// what got through, and can arrive late.
	private static let congestionHold: Duration = .seconds(10)
	/// An acknowledgement this slow from a relay a few tens of milliseconds away means a queue has built.
	private static let congestedAckDelayMs: UInt64 = 300
	private static let severeAckDelayMs: UInt64 = 800
	private static let maxResends = 2

	/// Decoded PCM frames (16 kHz mono) from the peer.
	public nonisolated let receivedAudio: AsyncStream<[Int16]>
	/// Pictures from the peer. Only the newest few wait: stale video is worse than a dropped frame.
	public nonisolated let receivedVideo: AsyncStream<CallVideoFrame>
	public nonisolated let videoSendEvents: AsyncStream<CallVideoSendEvent>
	/// Pictures from each participant of a group call. Roomier than `receivedVideo`, since several
	/// streams share it and a dropped picture costs its stream a keyframe.
	public nonisolated let receivedParticipantVideo: AsyncStream<CallParticipantVideoFrame>
	/// Reactions from the others in a group call.
	public nonisolated let receivedReactions: AsyncStream<CallParticipantReaction>
	/// Yields when the peer has stopped sending anything, or the relay path has closed. A hang-up does
	/// not always reach this client as a stanza, and without this the call would stay up on its own.
	public nonisolated let peerGone: AsyncStream<Void>

	private let receivedContinuation: AsyncStream<[Int16]>.Continuation
	private let receivedVideoContinuation: AsyncStream<CallVideoFrame>.Continuation
	private let videoSendEventsContinuation: AsyncStream<CallVideoSendEvent>.Continuation
	private let peerGoneContinuation: AsyncStream<Void>.Continuation
	private let receivedParticipantVideoContinuation: AsyncStream<CallParticipantVideoFrame>.Continuation
	private let receivedReactionsContinuation: AsyncStream<CallParticipantReaction>.Continuation
	/// Participant-indexed receive state, once this is a group call.
	private var group: GroupMediaState?
	private var playoutTask: Task<Void, Never>?
	private var linkGeneration = 0
	private let linkFactory: @Sendable (String, UInt16) -> any CallRelayLink
	private var allocatePendingSince: ContinuousClock.Instant?
	private let peerSilenceTimeout: Duration
	private var lastPeerActivity: ContinuousClock.Instant?
	private var watchdogTask: Task<Void, Never>?
	/// What has arrived since the last media log, before any of it is authenticated.
	private var arrivedByPayloadType: [UInt8: Int] = [:]
	private var rtcpArrived = 0
	private var rtcpAccepted = 0
	private var lastMediaLog: ContinuousClock.Instant?
	private let configuration: Configuration
	private var link: any CallRelayLink
	private var relayToken: Data
	private var integrityKey: Data
	private var relayHost: String
	private var relayPort: UInt16
	private var pipeline: CallAudioPipeline
	private var video: CallVideoPipeline
	private var rtcpSendKeys: CallSRTPKeys
	private let rtcpReceiveKeys: CallSRTPKeys
	private var cname: [UInt8]
	private var audioCNAME: [UInt8]
	private var audioPacketsSent: UInt32 = 0
	private var audioOctetsSent: UInt32 = 0
	private let audioSSRC: UInt32
	private let tagLength: Int
	private var rtcpIndex: UInt32 = 1
	private var rtcpReplay = CallSRTCPReplayWindow()
	private var reception = CallRTPReceptionStats()
	private let encoder: CallOpusEncoder
	private let decoder: CallOpusDecoder
	private var allocateRequest: Data
	private var allocateTransactionID: Data

	private var isRunning = false
	private var isAllocated = false
	private var allocateError: Int??
	private var receiveTask: Task<Void, Never>?
	private var keepaliveTask: Task<Void, Never>?
	private var reportTask: Task<Void, Never>?

	private var isSendingVideo = false
	/// While set, only an IDR may go out: dependent pictures would prolong what the peer cannot decode.
	private var keyframeRequired = true
	private var keyframeAnnounced = false
	private var sentHistory: [UInt16: (packet: Data, resends: Int)] = [:]
	private var sentOrder = [UInt16]()
	private var lastVideoTimestamp: UInt32 = 0
	private var videoPacketsSent: UInt32 = 0
	private var videoOctetsSent: UInt32 = 0
	private var videoClockAnchor: (timestamp: UInt32, at: ContinuousClock.Instant)?
	private var videoBitrate = CallSession.initialVideoBitrate
	private var cleanReports = 0
	private var congestedUntil: ContinuousClock.Instant?
	private var linkPressure = SCTPAssociation.SendPressure()
	private var paceNext: ContinuousClock.Instant?
	private var paceSent = [(at: ContinuousClock.Instant, bytes: Int)]()
	private var paceSentBytes = 0
	private var peerKeyframeAskedAt: ContinuousClock.Instant?
	private var peerKeyframeStream: UInt32?
	private var peerKeyframePending = false
	/// A keyframe taken from the picture containing this gap is not proof of recovery.
	private var inboundGapTimestamp: UInt32?
	private let clock = ContinuousClock()
	private let startInstant = ContinuousClock.now

	public private(set) var consentRequestsAnswered = 0
	public private(set) var videoFramesSent = 0
	public private(set) var videoFramesReceived = 0
	public private(set) var videoPacketsRejected = 0
	public private(set) var videoPacketsLost = 0
	public private(set) var keyframesRequestedByPeer = 0
	public private(set) var keyframesRequestedFromPeer = 0
	public private(set) var videoPacketsResent = 0
	public private(set) var carriedAudioPackets = 0

	public private(set) var framesSent = 0
	public private(set) var framesReceived = 0
	public private(set) var packetsRejected = 0
	public private(set) var decodeFailures = 0
	public private(set) var keysRejected = 0
	/// Loudest decoded sample so far. Zero with packets arriving means the peer's audio decodes to silence.
	public private(set) var decodedPeak = 0

	/// Builds a session. `link` defaults to the DTLS+SCTP transport to the relay the call selected.
	public init(
		configuration: Configuration,
		link: (any CallRelayLink)? = nil,
		peerSilenceTimeout: Duration = CallSession.defaultPeerSilenceTimeout
	) throws {
		guard let endpoint = configuration.relay.mediaEndpoint(), let address = endpoint.primaryIPv4 else {
			throw CallSessionError.noRelay
		}
		guard configuration.relay.relayTokens.indices.contains(endpoint.tokenID),
			  !configuration.relay.relayTokens[endpoint.tokenID].isEmpty else {
			throw CallSessionError.missingRelayToken
		}
		guard let key = configuration.relay.relayKeyASCII, !key.isEmpty else {
			throw CallSessionError.missingIntegrityKey
		}

		let participantID = CallMediaCrypto.formatParticipantID(configuration.selfParticipantID)
		let ssrc = CallRelayAllocate.audioSSRC(callID: configuration.callID, participantID: participantID)
		let videoSSRC = CallRelayAllocate.videoSSRC(callID: configuration.callID, participantID: participantID)
		let transaction = try CallKeyMessage.generateCallKey().prefix(12)

		self.configuration = configuration
		self.peerSilenceTimeout = peerSilenceTimeout
		self.relayToken = configuration.relay.relayTokens[endpoint.tokenID]
		self.integrityKey = key
		self.relayHost = address.host
		self.relayPort = address.port
		self.link = link ?? CallRelayDialer(host: address.host, advertisedPort: address.port)
		self.linkFactory = { host, port in link ?? CallRelayDialer(host: host, advertisedPort: port) }
		self.audioSSRC = ssrc
		self.tagLength = configuration.relay.warpTagLength ?? CallMediaCrypto.warpTagLength
		self.pipeline = try CallAudioPipeline(
			callKey: configuration.callKey,
			selfParticipantID: configuration.selfParticipantID,
			peerParticipantID: configuration.peerParticipantID,
			ssrc: ssrc,
			tagLength: configuration.relay.warpTagLength ?? CallMediaCrypto.warpTagLength
		)
		self.video = try CallVideoPipeline(
			callKey: configuration.callKey,
			selfParticipantID: configuration.selfParticipantID,
			peerParticipantID: configuration.peerParticipantID,
			ssrc: videoSSRC,
			tagLength: configuration.relay.warpTagLength ?? CallMediaCrypto.warpTagLength
		)
		self.rtcpSendKeys = try CallMediaCrypto.deriveRTCPKeys(callKey: configuration.callKey, participantID: participantID)
		self.rtcpReceiveKeys = try CallMediaCrypto.deriveRTCPKeys(
			callKey: configuration.callKey,
			participantID: CallMediaCrypto.formatParticipantID(configuration.peerParticipantID)
		)
		self.cname = CallRTCP.cname(ssrc: videoSSRC, callKey: configuration.callKey)
		self.audioCNAME = CallRTCP.cname(ssrc: ssrc, callKey: configuration.callKey)
		self.encoder = try CallOpusEncoder()
		self.decoder = try CallOpusDecoder()
		self.allocateTransactionID = Data(transaction)
		guard let request = CallRelayAllocate.request(
			transactionID: Data(transaction),
			relayToken: relayToken,
			relayIPv4: address.host,
			relayPort: address.port,
			integrityKey: key,
			callID: configuration.callID,
			participantID: participantID
		) else {
			throw CallSessionError.noRelay
		}

		self.allocateRequest = request
		var continuation: AsyncStream<[Int16]>.Continuation!
		self.receivedAudio = AsyncStream { continuation = $0 }
		self.receivedContinuation = continuation
		(self.receivedVideo, self.receivedVideoContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(4))
		(self.videoSendEvents, self.videoSendEventsContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(8))
		(self.peerGone, self.peerGoneContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
		(self.receivedParticipantVideo, self.receivedParticipantVideoContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(48))
		(self.receivedReactions, self.receivedReactionsContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(32))
	}

	/// Connects to the relay and waits for the Allocate to succeed.
	public func start() async throws {
		guard !isRunning else {
			return
		}

		if let update = configuration.groupUpdate {
			try configureGroup(update: update, directPeer: false)
		}

		try await link.open()
		isRunning = true
		WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): relay channel open \(self.relayHost, privacy: .public):\(self.relayPort)")

		listenToLink()

		let deadline = ContinuousClock.now + Self.allocateTimeout
		while !isAllocated {
			if let rejected = allocateError {
				await stop()
				throw CallSessionError.allocateRejected(rejected)
			}
			guard ContinuousClock.now < deadline else {
				await stop()
				throw CallSessionError.allocateTimedOut
			}

			try? await link.send(allocateRequest)
			let retryAt = ContinuousClock.now + Self.allocateRetryInterval
			while !isAllocated, allocateError == nil, ContinuousClock.now < retryAt {
				try? await Task.sleep(for: .milliseconds(20))
			}
		}

		WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): relay allocated")
		keepaliveTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: Self.keepaliveInterval)
				await self?.sendKeepalive()
			}
		}
		reportTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: Self.reportInterval)
				await self?.sendVideoReport()
			}
		}
		let watchdogInterval = min(peerSilenceTimeout / 4, .seconds(1))
		watchdogTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: watchdogInterval)
				await self?.checkPeerActivity()
				await self?.adaptToLink()
			}
		}
		if group != nil {
			startPlayout()
		}
		if isSendingVideo {
			requireKeyframe()
		}
	}

	private func listenToLink() {
		linkGeneration += 1
		let generation = linkGeneration
		let messages = link.messages
		receiveTask = Task { [weak self] in
			for await message in messages {
				await self?.handle(message)
			}
			await self?.relayEnded(generation: generation)
		}
	}

	/// Encodes and sends one 60 ms microphone frame (960 samples at 16 kHz).
	public func sendAudio(_ samples: [Int16]) async throws {
		// A group re-allocates during the call, and the relay already knows this device meanwhile. Going
		// quiet until it answers is what would look like having left.
		guard isRunning, isAllocated || group != nil else {
			throw CallSessionError.notRunning
		}
		// A group's media waits for its key: there is nobody who could decrypt this yet.
		guard isGroupEpochReady else {
			return
		}

		let opus = try encoder.encode(samples)
		let packet = try pipeline.protect(opus)
		try await link.send(packet)
		framesSent += 1
		audioPacketsSent &+= 1
		audioOctetsSent &+= UInt32(truncatingIfNeeded: opus.count)
	}

	// MARK: Sending video

	/// Lets our camera's pictures onto the wire, or stops them. The first picture after turning on must
	/// be an IDR, and the owner of the encoder is told so.
	public func setVideoSending(_ sending: Bool) {
		isSendingVideo = sending
		if sending {
			keyframeAnnounced = false
			requireKeyframe()
		}
	}

	/// Sends one Annex-B access unit. `timestamp` is its capture time on the 90 kHz clock. Returns once
	/// the last packet has left, which the pacer may hold back for a keyframe.
	public func sendVideo(
		_ accessUnit: Data,
		timestamp: UInt32,
		capturedAt: ContinuousClock.Instant? = nil
	) async throws {
		guard isRunning, isAllocated || group != nil else {
			throw CallSessionError.notRunning
		}
		guard isSendingVideo else {
			return
		}

		let isIDR = CallH264.hasIDR(accessUnit)
		guard isGroupEpochReady else {
			// Discarded, an IDR included, so one has to be asked for again once the key arrives.
			if isIDR {
				keyframeAnnounced = false
			}
			return
		}

		if keyframeRequired, !isIDR {
			requireKeyframe()
			return
		}
		guard videoPacketsSent == 0 || Int32(bitPattern: timestamp &- lastVideoTimestamp) >= 0 else {
			return
		}

		keyframeRequired = false
		keyframeAnnounced = false
		lastVideoTimestamp = timestamp
		videoClockAnchor = (timestamp, capturedAt ?? clock.now)

		let payloads = CallH264.packetize(accessUnit)
		let frameInfo = isIDR ? CallVideoRTPHeader.frameInfoIDR : 0
		for (index, payload) in payloads.enumerated() {
			await waitForPacer()
			// A requested group key can close the gate while a picture is leaving.
			guard isRunning, isSendingVideo, isGroupEpochReady else {
				return
			}

			let protected = try video.protect(
				payload,
				marker: index == payloads.count - 1,
				timestamp: timestamp,
				frameInfo: frameInfo,
				shortOffset: Self.shortOffset(since: capturedAt, now: clock.now)
			)
			remember(protected.packet, sequence: protected.sequence)
			videoPacketsSent &+= 1
			videoOctetsSent &+= UInt32(truncatingIfNeeded: payload.count)
			paceSentPacket(bytes: protected.packet.count)
			try await link.send(protected.packet)
		}
		videoFramesSent += 1
	}

	/// Milliseconds from a picture's capture to its packet's transmission.
	static func shortOffset(since capturedAt: ContinuousClock.Instant?, now: ContinuousClock.Instant) -> Int16 {
		guard let capturedAt else {
			return 0
		}

		let (seconds, attoseconds) = capturedAt.duration(to: now).components
		let ms = seconds * 1000 + attoseconds / 1_000_000_000_000_000
		return Int16(clamping: max(ms, 0))
	}

	private func requireKeyframe() {
		keyframeRequired = true
		guard isSendingVideo, !keyframeAnnounced else {
			return
		}

		keyframeAnnounced = true
		videoSendEventsContinuation.yield(.keyframeNeeded)
	}

	private func remember(_ packet: Data, sequence: UInt16) {
		if sentOrder.count == Self.sentHistorySize {
			sentHistory.removeValue(forKey: sentOrder.removeFirst())
		}
		sentOrder.append(sequence)
		sentHistory[sequence] = (packet, 0)
	}

	private func waitForPacer() async {
		guard let next = paceNext else {
			return
		}

		let allowedAt = next - Self.paceBurst
		if clock.now < allowedAt {
			try? await Task.sleep(until: allowedAt, clock: clock)
		}
	}

	private func paceSentPacket(bytes: Int) {
		let now = clock.now
		while let oldest = paceSent.first, oldest.at.duration(to: now) >= Self.paceWindow {
			paceSent.removeFirst()
			paceSentBytes -= oldest.bytes
		}
		paceSent.append((now, bytes))
		paceSentBytes += bytes

		let rate = max(Double(paceSentBytes * 8) * Self.paceFactor, Self.paceFloorBps)
		// An idle pacer starts from now: time with nothing to send is not a credit to spend on a burst.
		let start = max(paceNext ?? now, now)
		paceNext = start + .seconds(Double(bytes * 8) / rate)
	}

	// MARK: Keyframes from the peer

	/// Asks the peer for a keyframe by RTCP PLI, for a decoder that lost or cannot use a picture.
	/// Throttled, so calling it for every such picture is fine. An ordinary request that is throttled
	/// goes out when the interval ends unless a keyframe arrives first.
	public func requestPeerKeyframe(urgent: Bool = false) async {
		guard isRunning, isAllocated, let inbound = video.inboundSSRC else {
			return
		}

		let interval = urgent ? Self.urgentPeerKeyframeInterval : Self.peerKeyframeInterval
		if peerKeyframeStream == inbound, let asked = peerKeyframeAskedAt, asked.duration(to: clock.now) < interval {
			if !urgent {
				peerKeyframePending = true
			}
			return
		}

		peerKeyframeStream = inbound
		peerKeyframeAskedAt = clock.now
		peerKeyframePending = false
		keyframesRequestedFromPeer += 1
		await sendRTCP(CallRTCP.pictureLossIndication(senderSSRC: video.ssrc, mediaSSRC: inbound))
	}

	public func stop() async {
		guard isRunning || receiveTask != nil else {
			return
		}

		WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): stopped sent=\(self.framesSent) received=\(self.framesReceived) rejected=\(self.packetsRejected) badKeys=\(self.keysRejected) undecodable=\(self.decodeFailures) decodedPeak=\(self.decodedPeak) carried=\(self.carriedAudioPackets) consent=\(self.consentRequestsAnswered) videoSent=\(self.videoFramesSent) videoReceived=\(self.videoFramesReceived) videoLost=\(self.videoPacketsLost) videoRejected=\(self.videoPacketsRejected) resent=\(self.videoPacketsResent) keyframesAsked=\(self.keyframesRequestedByPeer)/\(self.keyframesRequestedFromPeer) bitrate=\(self.videoBitrate)")
		isRunning = false
		isAllocated = false
		keepaliveTask?.cancel()
		receiveTask?.cancel()
		reportTask?.cancel()
		watchdogTask?.cancel()
		playoutTask?.cancel()
		keepaliveTask = nil
		receiveTask = nil
		reportTask = nil
		watchdogTask = nil
		playoutTask = nil
		await link.close()
		receivedContinuation.finish()
		receivedVideoContinuation.finish()
		receivedParticipantVideoContinuation.finish()
		receivedReactionsContinuation.finish()
		group?.cancelReactionResends()
		videoSendEventsContinuation.finish()
		peerGoneContinuation.finish()
	}

	// MARK: Receiving

	private func handle(_ received: Data) async {
		// Before the checks below: the first byte of a group relay's envelope reads as STUN.
		guard isRunning, let message = CallRelayForwarding.unwrap(received), let first = message.first else {
			return
		}

		if first & 0xc0 == 0 {
			await handleSTUN(message)
		} else if first >> 6 == 2 {
			// RTP and RTCP share the path. RFC 5761 keeps their payload types from overlapping.
			if message.count > 1, (192...223).contains(message[message.startIndex + 1]) {
				await handleRTCP(message)
			} else {
				await handleRTP(message)
			}
		}
	}

	private func handleSTUN(_ message: Data) async {
		// The relay asks now and then whether this device is still there (RFC 7675), and a device that
		// never answers can be taken to have gone.
		if CallSTUN.messageType(message) == CallSTUN.bindingRequest, let transaction = CallSTUN.transactionID(message) {
			consentRequestsAnswered += 1
			try? await link.send(CallSTUN.encode(
				type: CallSTUN.bindingSuccess,
				transactionID: transaction,
				integrityKey: integrityKey,
				includeFingerprint: true
			))
			return
		}

		// A group call re-allocates as its roster changes. An answer to an older request says nothing
		// about the credentials now in use.
		if group != nil, CallSTUN.transactionID(message) != allocateTransactionID {
			return
		}

		if CallSTUN.isAllocateOrBindingSuccess(message) {
			if group != nil, !isAllocated, isRunning {
				WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): new relay allocation answered")
			}
			isAllocated = true
			allocatePendingSince = nil
		} else if CallSTUN.isAllocateError(message) {
			allocateError = .some(CallSTUN.errorCode(message))
			if group != nil {
				WhatsAppLog.logger.error("call \(self.configuration.callID, privacy: .public): relay refused an allocation, code \(CallSTUN.errorCode(message) ?? 0)")
			}
		}
	}

	/// Audio and video share keys but have separate SSRCs and rollover counters, so packets are told
	/// apart by payload type before anything is verified.
	private func handleRTP(_ message: Data) async {
		guard let header = CallRTPHeader.parse(message) else {
			packetsRejected += 1
			return
		}

		arrivedByPayloadType[header.payloadType, default: 0] += 1
		if let group {
			await handleGroupRTP(message, header: header, group: group)
		} else if header.payloadType == CallVideoRTPHeader.h264PayloadType {
			await handleVideoPacket(message)
		} else if CallRTPHeader.isAudioPayloadType(header.payloadType) {
			handleAudioPacket(message)
		} else {
			// The peer's video FEC, retransmissions and app data, which carry its audio too.
			if let audio = try? video.unprotectAuxiliary(message) {
				lastPeerActivity = clock.now
				handleCarriedAudio(audio)
			}
		}
	}

	private func handleAudioPacket(_ message: Data) {
		var received: CallAudioPipeline.Received?
		do {
			received = try pipeline.unprotect(message)
			lastPeerActivity = clock.now
			try decodeAudio(received?.payload ?? Data())
		} catch CallAudioPipeline.ReceiveError.authenticationFailed {
			packetsRejected += 1
			keysRejected += 1
		} catch is CallAudioPipeline.ReceiveError {
			packetsRejected += 1
		} catch {
			packetsRejected += 1
			decodeFailures += 1
			if decodeFailures <= 5, let received {
				let first = received.payload.prefix(4).map { String(format: "%02x", $0) }.joined()
				WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): undecodable packet pt=\(received.header.payloadType) bytes=\(received.payload.count) first=\(first, privacy: .public)")
			}
		}
	}

	private func decodeAudio(_ opus: Data) throws {
		let pcm = try decoder.decode(opus)
		framesReceived += 1
		for sample in pcm {
			decodedPeak = max(decodedPeak, abs(Int(sample)))
		}
		receivedContinuation.yield(pcm)
	}

	/// Audio inside a video packet that has authenticated. A WhatsApp client in a video call sends its
	/// speech this way whenever a video packet is going out.
	private func handleCarriedAudio(_ packet: Data?) {
		guard let packet, let received = pipeline.acceptCarried(packet) else {
			return
		}

		carriedAudioPackets += 1
		do {
			try decodeAudio(received.payload)
		} catch {
			decodeFailures += 1
		}
	}

	private func handleVideoPacket(_ message: Data) async {
		let received: CallVideoPipeline.Received
		do {
			received = try video.unprotect(message)
		} catch {
			videoPacketsRejected += 1
			if case CallAudioPipeline.ReceiveError.authenticationFailed = error {
				keysRejected += 1
			}
			return
		}

		lastPeerActivity = clock.now
		handleCarriedAudio(received.carriedAudio)
		guard received.isCurrentStream else {
			return
		}

		reception.observe(
			ssrc: received.header.ssrc,
			sequence: received.header.sequenceNumber,
			timestamp: received.header.timestamp,
			arrivalMs: monotonicMs(),
			payload: received.payloadBytes
		)
		if received.lost > 0 {
			videoPacketsLost += Int(received.lost)
			inboundGapTimestamp = received.header.timestamp
		}
		for frame in received.frames {
			videoFramesReceived += 1
			let afterGap = inboundGapTimestamp.map { Int32(bitPattern: frame.timestamp &- $0) > 0 } ?? true
			if frame.isKeyframe, afterGap {
				peerKeyframePending = false
				inboundGapTimestamp = nil
			}
			receivedVideoContinuation.yield(frame)
		}
		if received.lost > 0 {
			// A missing reference picture can damage later frames without any decoder error.
			await requestPeerKeyframe()
		}
	}

	private func handleRTCP(_ message: Data) async {
		rtcpArrived += 1
		guard message.count >= 8 else {
			return
		}

		let bytes = [UInt8](message.prefix(8))
		let sender = (4..<8).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[$1]) }
		if let group {
			await handleGroupRTCP(message, sender: sender, group: group)
			return
		}

		guard let (plain, index) = CallMediaCrypto.unprotectRTCP(message, keys: rtcpReceiveKeys, senderSSRC: sender),
			  rtcpReplay.accept(sender: sender, index: index),
			  let summary = CallRTCP.parse(plain) else {
			return
		}

		lastPeerActivity = clock.now
		rtcpAccepted += 1
		for timing in summary.senderTimings {
			reception.observeSenderReport(ssrc: timing.ssrc, compactNTP: timing.compactNTP, arrivalMs: monotonicMs())
		}
		await applyFeedback(summary)
	}

	/// What the far side's RTCP asks of what this side sends.
	private func applyFeedback(_ summary: CallRTCP.Summary) async {
		if CallRTCP.requestsKeyframe(summary.feedback, ssrc: video.ssrc) {
			keyframesRequestedByPeer += 1
			keyframeAnnounced = false
			requireKeyframe()
		}
		if let block = summary.reportBlocks.last(where: { $0.ssrc == video.ssrc }) {
			adaptBitrate(fractionLost: block.fractionLost)
		}
		if isSendingVideo {
			for sequence in CallRTCP.nackedSequences(summary.feedback, ssrc: video.ssrc) {
				guard var entry = sentHistory[sequence], entry.resends < Self.maxResends else {
					continue
				}

				entry.resends += 1
				sentHistory[sequence] = entry
				videoPacketsResent += 1
				try? await link.send(entry.packet)
			}
		}
	}

	/// Backs off quickly on reported loss and creeps back up after a run of clean reports.
	private func adaptBitrate(fractionLost: UInt8) {
		var next = videoBitrate
		if fractionLost > 26 {
			next = Int(Double(videoBitrate) * 0.8)
			cleanReports = 0
		} else if fractionLost > 8 {
			next = Int(Double(videoBitrate) * 0.95)
			cleanReports = 0
		} else if congestedUntil.map({ clock.now >= $0 }) ?? true {
			cleanReports += 1
			if cleanReports >= 3 {
				next = Int(Double(videoBitrate) * 1.08)
				cleanReports = 0
			}
		}

		setVideoBitrate(next)
	}

	private func setVideoBitrate(_ value: Int) {
		let ceiling = group == nil ? Self.maximumVideoBitrate : Self.maximumGroupVideoBitrate
		let next = min(max(value, Self.minimumVideoBitrate), ceiling)
		guard next != videoBitrate else {
			return
		}

		videoBitrate = next
		videoSendEventsContinuation.yield(.targetBitrate(next))
	}

	/// Reads this side's own view of the path. The peer's loss reports cannot be the only signal: when
	/// the uplink saturates, they stop arriving along with everything else, and the encoder would go on
	/// feeding the queue that is stopping them.
	func adaptToLink() async {
		guard isRunning, isSendingVideo, let pressure = await link.sendPressure() else {
			return
		}

		linkPressure = pressure
		let delay = pressure.ackDelayMs ?? 0
		let abandoned = pressure.sent > 0 ? Double(pressure.abandoned) / Double(pressure.sent) : 0
		let severe = delay >= Self.severeAckDelayMs || abandoned >= 0.25
		guard severe || delay >= Self.congestedAckDelayMs || abandoned >= 0.05 else {
			return
		}

		WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): congested ack=\(delay)ms abandoned=\(pressure.abandoned)/\(pressure.sent) bitrate=\(self.videoBitrate)")
		congestedUntil = clock.now + Self.congestionHold
		cleanReports = 0
		setVideoBitrate(Int(Double(videoBitrate) * (severe ? 0.6 : 0.8)))
	}

	/// The periodic report, once video flows in either direction. It also retries a keyframe request
	/// the throttle held back.
	private func sendVideoReport() async {
		if let group {
			await sendGroupReports(group)
			return
		}

		guard isRunning, isAllocated, isSendingVideo || video.inboundSSRC != nil else {
			return
		}

		if peerKeyframePending, peerKeyframeAskedAt.map({ $0.duration(to: clock.now) >= Self.peerKeyframeInterval }) ?? true {
			await requestPeerKeyframe()
		}

		await sendRTCP(videoSenderReport(report: reception.report(nowMs: monotonicMs())))
	}

	private func videoSenderReport(report: CallRTCP.ReceptionReport?) -> Data {
		// The media clock at this instant, read from the newest picture's capture: pairing a send time
		// with a capture-stamped timestamp would tell the peer every picture was taken later than it was.
		var timestamp = lastVideoTimestamp
		if let anchor = videoClockAnchor {
			let (seconds, attoseconds) = anchor.at.duration(to: clock.now).components
			let ticks = Double(seconds) * Double(CallVideoRTPHeader.clockRate)
				+ Double(attoseconds) * 1e-18 * Double(CallVideoRTPHeader.clockRate)
			timestamp = anchor.timestamp &+ UInt32(truncatingIfNeeded: Int64(ticks))
		}
		return CallRTCP.senderReport(
			ssrc: video.ssrc,
			rtpTimestamp: timestamp,
			packetsSent: videoPacketsSent,
			octetsSent: videoOctetsSent,
			wallclockMs: UInt64(Date().timeIntervalSince1970 * 1000),
			cname: cname,
			report: report
		)
	}

	private func sendRTCP(_ plain: Data, senderSSRC: UInt32? = nil) async {
		guard let protected = try? CallMediaCrypto.protectRTCP(
			plain,
			keys: rtcpSendKeys,
			senderSSRC: senderSSRC ?? video.ssrc,
			index: rtcpIndex
		) else {
			return
		}

		rtcpIndex &+= 1
		try? await link.send(protected)
	}

	private func monotonicMs() -> UInt64 {
		let (seconds, attoseconds) = startInstant.duration(to: clock.now).components
		return UInt64(seconds) * 1000 + UInt64(attoseconds / 1_000_000_000_000_000)
	}

	private func sendKeepalive() async {
		guard isRunning else {
			return
		}

		try? await link.send(allocateRequest)
		let transaction = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
		try? await link.send(CallSTUN.ping(transactionID: transaction))
	}

	private func relayEnded(generation: Int) async {
		// A link replaced mid-call ends without that meaning anything.
		guard isRunning, generation == linkGeneration else {
			return
		}

		WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): relay path closed")
		peerGoneContinuation.yield()
		await stop()
	}

	/// What the peer has been sending, every few seconds, by RTP payload type. Tells a peer that stopped
	/// sending apart from one whose packets this client does not use.
	private func logMediaArrivals() {
		guard isRunning else {
			return
		}

		let now = clock.now
		guard let last = lastMediaLog else {
			lastMediaLog = now
			return
		}
		guard last.duration(to: now) >= .seconds(5) else {
			return
		}

		let rtp = arrivedByPayloadType.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
		WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): arrived rtp[\(rtp, privacy: .public)] rtcp=\(self.rtcpArrived)/\(self.rtcpAccepted) frames video=\(self.videoFramesReceived) audio=\(self.framesReceived) carried=\(self.carriedAudioPackets) rejected=\(self.videoPacketsRejected)/\(self.packetsRejected) sentVideo=\(self.videoFramesSent) bitrate=\(self.videoBitrate) ack=\(self.linkPressure.ackDelayMs ?? 0)ms abandoned=\(self.linkPressure.abandoned)/\(self.linkPressure.sent)")
		arrivedByPayloadType = [:]
		rtcpArrived = 0
		rtcpAccepted = 0
		lastMediaLog = now
	}

	/// Only authenticated traffic counts, so nothing but the peer can keep a call alive. A call that
	/// has not heard from the peer yet waits, since media can take a moment to start.
	private func checkPeerActivity() {
		logMediaArrivals()
		if group != nil {
			// Nothing to hear is ordinary in a group, where the roster says who is there. The one thing
			// that does end it here is a relay that stopped answering a new allocation.
			if isRunning, let pending = allocatePendingSince, pending.duration(to: clock.now) >= Self.allocateTimeout {
				WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): the relay did not answer a new allocation")
				allocatePendingSince = nil
				peerGoneContinuation.yield()
			}
			return
		}

		guard isRunning, let last = lastPeerActivity, last.duration(to: clock.now) >= peerSilenceTimeout else {
			return
		}

		WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): nothing from the peer for \(self.peerSilenceTimeout, privacy: .public)")
		lastPeerActivity = nil
		peerGoneContinuation.yield()
	}
}

// MARK: - Group calls

/// Everything a group call adds to a session. The engine this follows keeps it optional in the same way,
/// which leaves the 1:1 path as it is.
private final class GroupMediaState {
	var registry: CallGroupMediaRegistry
	let streams: CallRelayAllocate.GroupStreams
	/// The relay allocation held: absent, or held with or without a number.
	var relayTransaction: UInt32??
	var localEpochTransaction: UInt32?
	var requiredEpochTransaction: UInt32?
	/// A promoted 1:1 call keeps using its call key until a group key replaces it.
	var isDirectFallbackActive: Bool
	var mixer = CallGroupAudioMixer()
	var decoders = [String: CallOpusDecoder]()
	var audioReception = [String: CallRTPReceptionStats]()
	var videoReception = [String: CallRTPReceptionStats]()
	var rtcpReplay = [String: CallSRTCPReplayWindow]()
	var keyframeAskedAt = [String: ContinuousClock.Instant]()
	var keyframePending = Set<String>()
	var nextPlayout: ContinuousClock.Instant?
	/// This device's app data stream, which reactions go out on.
	var appData: CallAudioPipeline
	var reactionTransaction: UInt64 = 0
	/// The newest reaction seen from each participant. A new media session starts its numbering over.
	var reactionsSeen = [String: (pid: UInt32?, transaction: UInt64)]()
	var reactionResends = [UInt64: Task<Void, Never>]()

	init(
		registry: CallGroupMediaRegistry,
		streams: CallRelayAllocate.GroupStreams,
		appData: CallAudioPipeline,
		requiredEpochTransaction: UInt32?,
		isDirectFallbackActive: Bool
	) {
		self.registry = registry
		self.streams = streams
		self.appData = appData
		self.requiredEpochTransaction = requiredEpochTransaction
		self.isDirectFallbackActive = isDirectFallbackActive
	}

	var isEpochReady: Bool {
		if let requiredEpochTransaction {
			return localEpochTransaction.map { $0 >= requiredEpochTransaction } ?? false
		}

		return localEpochTransaction != nil || isDirectFallbackActive
	}

	/// Forgets a participant's decode state, whose stream it no longer describes.
	func resetParticipant(_ id: String) {
		mixer.reset(id)
		decoders.removeValue(forKey: id)
		audioReception.removeValue(forKey: id)
		videoReception.removeValue(forKey: id)
		rtcpReplay.removeValue(forKey: id)
		keyframeAskedAt.removeValue(forKey: id)
		keyframePending.remove(id)
		reactionsSeen.removeValue(forKey: id)
	}

	func cancelReactionResends() {
		reactionResends.values.forEach { $0.cancel() }
		reactionResends = [:]
	}

	func retainParticipants(_ active: Set<String>) {
		mixer.retain(registry.activeParticipantIDs)
		decoders = decoders.filter { active.contains($0.key) }
		audioReception = audioReception.filter { active.contains($0.key) }
		videoReception = videoReception.filter { active.contains($0.key) }
		rtcpReplay = rtcpReplay.filter { active.contains($0.key) }
		keyframeAskedAt = keyframeAskedAt.filter { active.contains($0.key) }
		keyframePending = keyframePending.filter { active.contains($0) }
		reactionsSeen = reactionsSeen.filter { active.contains($0.key) }
	}
}

extension CallSession {
	/// A relay's allocation, in the form a re-allocation needs it.
	private struct GroupRelayRefresh {
		let host: String
		let port: UInt16
		let token: Data
		let integrityKey: Data
		let tagLength: Int
	}

	/// Whether this session has become a group call.
	public var isGroupCall: Bool {
		group != nil
	}

	private var isGroupEpochReady: Bool {
		group?.isEpochReady ?? true
	}

	private var participantID: String {
		CallMediaCrypto.formatParticipantID(configuration.selfParticipantID)
	}

	// MARK: Roster

	/// Applies a committed roster. On a 1:1 call this is the moment it becomes a group call, and its peer
	/// stays heard on the call key until the first group key arrives.
	public func applyGroupUpdate(_ update: GroupCallUpdate) async throws {
		guard let group else {
			let previous = (host: relayHost, port: relayPort, token: relayToken, key: integrityKey)
			try configureGroup(update: update, directPeer: true)
			guard isRunning else {
				return
			}

			startPlayout()
			let moved = relayHost != previous.host || relayPort != previous.port
			if moved || relayToken != previous.token || integrityKey != previous.key {
				isAllocated = false
				allocatePendingSince = moved ? nil : clock.now
			}
			if moved {
				await reconnectRelay()
			}
			await transmitAllocate()
			return
		}

		// Everything that can fail about the relay is settled before the roster moves, so a corrected
		// resend of this transaction is not read as stale.
		let relayTransaction = update.relay.map(\.transactionID)
		let advancesRelay = relayTransaction.map { incoming in
			guard let held = group.relayTransaction else {
				return true
			}
			guard let next = incoming else {
				return false
			}

			return held.map { next > $0 } ?? true
		} ?? false
		let refresh = advancesRelay ? try relayRefresh(for: update) : nil
		if let refresh, refresh.tagLength != tagLength {
			throw CallGroupMediaError.tagLengthChanged
		}

		let previousPIDs = group.registry.activePIDs
		let previousDevices = group.registry.activeDeviceIDs
		let migrated = group.registry.participantsWithPIDChanges(update)
		let result = try group.registry.apply(update)
		if result == .applied {
			guard update.localDevice(matching: configuration.selfParticipantID) != nil else {
				throw CallGroupMediaError.localParticipantRemoved
			}

			if update.isRekeyRequested {
				group.requiredEpochTransaction = max(group.requiredEpochTransaction ?? 0, update.transactionID)
			}
			migrated.forEach(group.resetParticipant)
			group.retainParticipants(group.registry.activeDeviceIDs)

			if !update.isVideo {
				setVideoSending(false)
			} else if !group.registry.activeDeviceIDs.isSubset(of: previousDevices) {
				// Someone new has no reference pictures to decode from.
				forceKeyframe()
			}

			await commitGroupAllocate(group, refresh: refresh, subscriptionsChanged: group.registry.activePIDs != previousPIDs)
			syncGroupEpoch(group)
		} else if advancesRelay {
			// A relay refresh on a roster already processed: only the allocation moves.
			await commitGroupAllocate(group, refresh: refresh, subscriptionsChanged: false)
		}
		if advancesRelay {
			group.relayTransaction = relayTransaction
		}
	}

	/// Installs a shared media key, or holds it until its roster arrives.
	public func applyGroupEpoch(_ epoch: GroupCallEpoch) throws {
		guard let group else {
			throw CallSessionError.notRunning
		}

		_ = try group.registry.applyEpoch(transactionID: epoch.transactionID, key: epoch.key)
		syncGroupEpoch(group)
	}

	private func configureGroup(update: GroupCallUpdate, directPeer: Bool) throws {
		guard update.localDevice(matching: configuration.selfParticipantID) != nil else {
			throw CallGroupMediaError.localParticipantRemoved
		}

		let refresh = try relayRefresh(for: update)
		var registry = CallGroupMediaRegistry(
			callID: configuration.callID,
			callCreator: update.callCreator,
			localDevice: configuration.selfParticipantID,
			tagLength: tagLength
		)
		if directPeer {
			try registry.seedDirectPeer(
				callKey: configuration.callKey,
				userJID: CallJID.user(configuration.peerParticipantID),
				deviceJID: configuration.peerParticipantID,
				video: true
			)
		}
		_ = try registry.apply(update)

		let streams = CallRelayAllocate.GroupStreams.make(callID: configuration.callID, participantID: participantID)
		let state = GroupMediaState(
			registry: registry,
			streams: streams,
			appData: try CallAudioPipeline(
				callKey: configuration.callKey,
				selfParticipantID: participantID,
				peerParticipantID: configuration.peerParticipantID,
				ssrc: streams.appData,
				tagLength: tagLength,
				payloadType: CallAppData.payloadType,
				samplesPerPacket: CallAppData.timestampStride
			),
			requiredEpochTransaction: update.isRekeyRequested ? update.transactionID : nil,
			isDirectFallbackActive: directPeer
		)
		state.relayTransaction = update.relay.map(\.transactionID)
		state.mixer.retain(state.registry.activeParticipantIDs)
		group = state
		adoptAllocation(state, refresh: refresh)
		syncGroupEpoch(state)
		WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): group media, media=\(update.media, privacy: .public) transaction=\(update.transactionID) remotes=\(state.registry.activeDeviceIDs.count)")
	}

	private func relayRefresh(for update: GroupCallUpdate) throws -> GroupRelayRefresh? {
		guard let relay = update.relay?.forGroupMedia else {
			return nil
		}
		guard let endpoint = relay.mediaEndpoint(),
			  let address = endpoint.primaryIPv4,
			  relay.relayTokens.indices.contains(endpoint.tokenID),
			  !relay.relayTokens[endpoint.tokenID].isEmpty,
			  let key = relay.relayKeyASCII, !key.isEmpty else {
			throw CallGroupMediaError.invalidSnapshot
		}

		return GroupRelayRefresh(
			host: address.host,
			port: address.port,
			token: relay.relayTokens[endpoint.tokenID],
			integrityKey: key,
			tagLength: relay.warpTagLength ?? CallMediaCrypto.warpTagLength
		)
	}

	/// Rebuilds the Allocate from what is current. Sending it is up to the caller.
	private func adoptAllocation(_ group: GroupMediaState, refresh: GroupRelayRefresh?) {
		if let refresh {
			relayHost = refresh.host
			relayPort = refresh.port
			relayToken = refresh.token
			integrityKey = refresh.integrityKey
		}

		let transaction = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
		guard let request = CallRelayAllocate.groupRequest(
			transactionID: transaction,
			relayToken: relayToken,
			relayIPv4: relayHost,
			relayPort: relayPort,
			integrityKey: integrityKey,
			streams: group.streams,
			participantPIDs: group.registry.activePIDs
		) else {
			return
		}

		allocateRequest = request
		allocateTransactionID = transaction
	}

	private func commitGroupAllocate(
		_ group: GroupMediaState,
		refresh: GroupRelayRefresh?,
		subscriptionsChanged: Bool
	) async {
		let addressChanged = refresh.map { $0.host != relayHost || $0.port != relayPort } ?? false
		let credentialsChanged = refresh.map { $0.token != relayToken || $0.integrityKey != integrityKey } ?? false
		guard addressChanged || credentialsChanged || subscriptionsChanged else {
			return
		}

		adoptAllocation(group, refresh: refresh)
		if addressChanged || credentialsChanged {
			// New credentials invalidate the allocation, even on the same relay. A move starts the wait
			// for an answer once it has connected, since dialing is not the relay being slow to answer.
			isAllocated = false
			allocatePendingSince = addressChanged ? nil : clock.now
		}
		guard isRunning else {
			return
		}

		if addressChanged {
			await reconnectRelay()
		}
		await transmitAllocate()
	}

	private func transmitAllocate() async {
		try? await link.send(allocateRequest)
	}

	/// Moves to the relay a new allocation names. Nothing can be sent or heard until it answers.
	private func reconnectRelay() async {
		WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): moving to relay \(self.relayHost, privacy: .public):\(self.relayPort)")
		let previous = link
		receiveTask?.cancel()
		let replacement = linkFactory(relayHost, relayPort)
		link = replacement
		listenToLink()
		let generation = linkGeneration
		await previous.close()
		// Each await is a chance to have hung up, or to have moved again.
		guard isRunning, generation == linkGeneration else {
			await replacement.close()
			return
		}

		do {
			try await replacement.open()
			guard isRunning, generation == linkGeneration else {
				await replacement.close()
				return
			}

			allocatePendingSince = clock.now
		} catch {
			guard isRunning, generation == linkGeneration else {
				return
			}

			WhatsAppLog.logger.error("call \(self.configuration.callID, privacy: .public): relay move failed: \(String(describing: error), privacy: .public)")
			peerGoneContinuation.yield()
		}
	}

	/// Moves what this side sends to the key the registry has installed. Everything derives before any
	/// live stream changes, so a failure leaves them all on the last key.
	private func syncGroupEpoch(_ group: GroupMediaState) {
		guard let epoch = group.registry.installedEpoch,
			  group.localEpochTransaction.map({ epoch.transactionID > $0 }) ?? true,
			  let sendKeys = try? CallMediaCrypto.deriveRTCPKeys(callKey: epoch.key, participantID: participantID) else {
			return
		}

		var audio = pipeline
		var pictures = video
		var appData = group.appData
		do {
			try audio.rekeySend(callKey: epoch.key, selfParticipantID: participantID)
			try pictures.rekeySend(callKey: epoch.key, selfParticipantID: participantID)
			try appData.rekeySend(callKey: epoch.key, selfParticipantID: participantID)
		} catch {
			return
		}

		pipeline = audio
		video = pictures
		group.appData = appData
		// Whoever a new key keeps out must not get the repeats of a reaction under it.
		group.cancelReactionResends()
		rtcpSendKeys = sendKeys
		cname = CallRTCP.cname(ssrc: video.ssrc, callKey: epoch.key)
		audioCNAME = CallRTCP.cname(ssrc: audioSSRC, callKey: epoch.key)
		group.localEpochTransaction = epoch.transactionID
		group.isDirectFallbackActive = false
		// What is kept for NACKs is protected under the last key, which a removed member still holds.
		sentHistory = [:]
		sentOrder = []
		group.mixer.retain(group.registry.activeParticipantIDs)
		// The first decryptable media for someone just admitted must not depend on an earlier picture.
		forceKeyframe()
	}

	private func forceKeyframe() {
		keyframeAnnounced = false
		requireKeyframe()
	}

	// MARK: Receiving

	private func handleGroupRTP(_ message: Data, header: CallRTPHeader, group: GroupMediaState) async {
		// A requested key retires the last one at once, so a removed member cannot go on sending under it.
		guard group.isEpochReady else {
			return
		}

		if header.payloadType == CallVideoRTPHeader.h264PayloadType {
			await handleGroupVideo(message, header: header, group: group)
		} else if CallRTPHeader.isAudioPayloadType(header.payloadType) {
			handleGroupAudio(message, header: header, group: group)
		} else if header.payloadType == CallAppData.payloadType,
				  let id = group.registry.participantID(forAppData: header.ssrc) {
			handleGroupAppData(message, from: id, group: group)
		} else if let id = group.registry.participantID(forSlot: header.ssrc),
				  let carried = try? group.registry.unprotectAuxiliary(message, from: id) {
			decodeCarriedAudio(carried, from: id, group: group)
		}
	}

	private func handleGroupAudio(_ message: Data, header: CallRTPHeader, group: GroupMediaState) {
		// Without a route it is not addressed to anyone this call knows, such as a straggler from someone
		// who just left, and no key was tried on it.
		guard let id = group.registry.participantID(forAudio: header.ssrc) else {
			return
		}

		do {
			guard let received = try group.registry.unprotectAudio(message, from: id) else {
				return
			}
			// A lone byte is a sender saying it has nothing to say, and is no frame to decode.
			guard received.payload.count > 1 else {
				return
			}

			group.audioReception[id, default: CallRTPReceptionStats()].observe(
				ssrc: header.ssrc,
				sequence: header.sequenceNumber,
				timestamp: header.timestamp,
				arrivalMs: monotonicMs(),
				payload: received.payload.count
			)
			decodeGroupAudio(received.payload, from: id, group: group)
		} catch CallAudioPipeline.ReceiveError.authenticationFailed {
			packetsRejected += 1
			keysRejected += 1
		} catch {
			packetsRejected += 1
		}
	}

	/// Each reaction arrives several times, and only its first counts.
	private func handleGroupAppData(_ message: Data, from id: String, group: GroupMediaState) {
		do {
			guard let received = try group.registry.unprotectAppData(message, from: id),
				  let receiver = group.registry.receivers[id] else {
				return
			}

			var seen = group.reactionsSeen[id] ?? (pid: receiver.pid, transaction: 0)
			if seen.pid != receiver.pid {
				seen = (receiver.pid, 0)
			}
			for reaction in try CallAppData.decode(received.payload) where reaction.transactionID > seen.transaction {
				seen.transaction = reaction.transactionID
				receivedReactionsContinuation.yield(CallParticipantReaction(
					participantID: id,
					userJID: receiver.userJID,
					emoji: reaction.emoji.isEmpty ? nil : reaction.emoji
				))
			}
			group.reactionsSeen[id] = seen
		} catch {
			packetsRejected += 1
		}
	}

	private func handleGroupVideo(_ message: Data, header: CallRTPHeader, group: GroupMediaState) async {
		guard let id = group.registry.participantID(forVideo: header.ssrc) else {
			return
		}

		let received: CallVideoPipeline.Received
		do {
			guard let unprotected = try group.registry.unprotectVideo(message, from: id) else {
				return
			}

			received = unprotected
		} catch {
			videoPacketsRejected += 1
			if case CallAudioPipeline.ReceiveError.authenticationFailed = error {
				keysRejected += 1
			}
			return
		}

		decodeCarriedAudio(received.carriedAudio, from: id, group: group)
		guard received.isCurrentStream else {
			return
		}

		group.videoReception[id, default: CallRTPReceptionStats()].observe(
			ssrc: received.header.ssrc,
			sequence: received.header.sequenceNumber,
			timestamp: received.header.timestamp,
			arrivalMs: monotonicMs(),
			payload: received.payloadBytes
		)
		if received.lost > 0 {
			videoPacketsLost += Int(received.lost)
		}
		for frame in received.frames {
			videoFramesReceived += 1
			if frame.isKeyframe {
				group.keyframePending.remove(id)
			}
			receivedParticipantVideoContinuation.yield(CallParticipantVideoFrame(participantID: id, frame: frame))
		}
		if received.lost > 0 {
			await requestParticipantKeyframe(id)
		}
	}

	private func decodeCarriedAudio(_ packet: Data?, from id: String, group: GroupMediaState) {
		guard let packet, let received = group.registry.acceptCarriedAudio(packet, from: id) else {
			return
		}

		carriedAudioPackets += 1
		decodeGroupAudio(received.payload, from: id, group: group)
	}

	/// Each participant has a decoder of their own: these codecs carry state from frame to frame, and one
	/// shared across speakers would corrupt all of them.
	private func decodeGroupAudio(_ opus: Data, from id: String, group: GroupMediaState) {
		do {
			let decoder: CallOpusDecoder
			if let existing = group.decoders[id] {
				decoder = existing
			} else {
				decoder = try CallOpusDecoder()
				group.decoders[id] = decoder
			}

			let pcm = try decoder.decode(opus)
			framesReceived += 1
			for sample in pcm {
				decodedPeak = max(decodedPeak, abs(Int(sample)))
			}
			group.mixer.push(id, pcm)
		} catch {
			packetsRejected += 1
			decodeFailures += 1
			if decodeFailures <= 5 {
				let first = opus.prefix(4).map { String(format: "%02x", $0) }.joined()
				WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): undecodable group audio from \(id, privacy: .public) bytes=\(opus.count) first=\(first, privacy: .public)")
			}
		}
	}

	private func handleGroupRTCP(_ message: Data, sender: UInt32, group: GroupMediaState) async {
		// A requested key retires the shared RTCP keys along with the media ones. A high index accepted
		// under the old key would also advance a replay window that outlives it.
		guard group.isEpochReady,
			  let id = group.registry.participantID(forSlot: sender),
			  let keys = group.registry.rtcpKeys(for: id),
			  let (plain, index) = CallMediaCrypto.unprotectRTCP(message, keys: keys, senderSSRC: sender),
			  group.rtcpReplay[id, default: CallSRTCPReplayWindow()].accept(sender: sender, index: index),
			  let summary = CallRTCP.parse(plain) else {
			return
		}

		rtcpAccepted += 1
		for timing in summary.senderTimings {
			group.audioReception[id]?.observeSenderReport(ssrc: timing.ssrc, compactNTP: timing.compactNTP, arrivalMs: monotonicMs())
			group.videoReception[id]?.observeSenderReport(ssrc: timing.ssrc, compactNTP: timing.compactNTP, arrivalMs: monotonicMs())
		}
		await applyFeedback(summary)
	}

	/// Asks one participant for a keyframe, for a decoder that lost or cannot use a picture. Throttled, so
	/// calling it for every such picture is fine.
	///
	/// The engine this follows sends none in a group, unsure whether a request travels end to end past
	/// the relay. Peers do honor one addressed to them, and a lost picture otherwise waits for the sender's
	/// next periodic keyframe, so it is worth asking.
	public func requestParticipantKeyframe(_ id: String) async {
		guard isRunning, let group,
			  let videoSSRC = group.registry.receivers[id]?.videoSSRC else {
			return
		}

		if let asked = group.keyframeAskedAt[id], asked.duration(to: clock.now) < Self.peerKeyframeInterval {
			group.keyframePending.insert(id)
			return
		}

		group.keyframeAskedAt[id] = clock.now
		group.keyframePending.remove(id)
		keyframesRequestedFromPeer += 1
		await sendRTCP(CallRTCP.pictureLossIndication(senderSSRC: video.ssrc, mediaSSRC: videoSSRC))
	}

	/// One Sender Report per stream received, since each participant reads the block about their own.
	private func sendGroupReports(_ group: GroupMediaState) async {
		guard isRunning, group.isEpochReady else {
			return
		}

		for id in group.keyframePending {
			await requestParticipantKeyframe(id)
		}

		let now = monotonicMs()
		let wallclock = UInt64(Date().timeIntervalSince1970 * 1000)
		var audioReports = [CallRTCP.ReceptionReport?]()
		for id in Array(group.audioReception.keys) {
			audioReports.append(group.audioReception[id]?.report(nowMs: now))
		}
		for report in audioReports.isEmpty ? [nil] : audioReports {
			await sendRTCP(CallRTCP.senderReport(
				ssrc: audioSSRC,
				rtpTimestamp: pipeline.nextTimestamp,
				packetsSent: audioPacketsSent,
				octetsSent: audioOctetsSent,
				wallclockMs: wallclock,
				cname: audioCNAME,
				report: report
			), senderSSRC: audioSSRC)
		}

		guard isSendingVideo || !group.videoReception.isEmpty else {
			return
		}

		var videoReports = [CallRTCP.ReceptionReport?]()
		for id in Array(group.videoReception.keys) {
			videoReports.append(group.videoReception[id]?.report(nowMs: now))
		}
		for report in videoReports.isEmpty ? [nil] : videoReports {
			await sendRTCP(videoSenderReport(report: report))
		}
	}

	// MARK: Reactions

	/// Sends a reaction to everyone in a group call. An empty one takes back the last. A 1:1 call has no
	/// app data stream to carry it.
	public func sendReaction(_ emoji: String) async throws {
		guard isRunning, let group, group.isEpochReady else {
			throw CallSessionError.notRunning
		}

		group.reactionTransaction &+= 1
		if group.reactionTransaction == 0 {
			group.reactionTransaction = 1
		}
		let transaction = group.reactionTransaction
		let payload = try CallAppData.encode(transactionID: transaction, emoji: emoji)
		try await sendAppData(payload, group: group)

		if group.reactionResends.count >= Self.maxReactionResends,
		   let oldest = group.reactionResends.keys.min() {
			group.reactionResends.removeValue(forKey: oldest)?.cancel()
		}
		group.reactionResends[transaction] = Task { [weak self] in
			for _ in 1..<CallAppData.sendCount {
				try? await Task.sleep(for: CallAppData.resendInterval)
				guard !Task.isCancelled else {
					return
				}

				await self?.resendReaction(payload)
			}
			await self?.finishReactionResends(transaction)
		}
	}

	private func resendReaction(_ payload: Data) async {
		guard isRunning, let group, group.isEpochReady else {
			return
		}

		try? await sendAppData(payload, group: group)
	}

	var pendingReactionResends: Int {
		group?.reactionResends.count ?? 0
	}

	private func finishReactionResends(_ transaction: UInt64) {
		group?.reactionResends.removeValue(forKey: transaction)
	}

	private func sendAppData(_ payload: Data, group: GroupMediaState) async throws {
		let packet = try group.appData.protect(payload)
		try await link.send(packet)
	}

	// MARK: Playout

	private func startPlayout() {
		guard playoutTask == nil else {
			return
		}

		playoutTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: Self.groupPlayoutInterval)
				await self?.drainMixer()
			}
		}
	}

	/// Plays what the mixer has on a steady clock. Silence is simply not played: the device needs no
	/// filler, and a late tick catches up rather than letting the queues run ahead of real time.
	private func drainMixer() {
		guard isRunning, let group else {
			return
		}

		let now = clock.now
		var next = group.nextPlayout ?? now
		// Far behind, as after sleep: resume from now rather than playing out a backlog at once.
		if next.duration(to: now) > .milliseconds(200) {
			next = now
		}
		while next <= now {
			let first = group.mixer.mixChunk()
			let second = group.mixer.mixChunk()
			if first != nil || second != nil {
				let silence = [Int16](repeating: 0, count: CallGroupAudioMixer.chunkSamples)
				receivedContinuation.yield((first ?? silence) + (second ?? silence))
			}
			next += Self.groupPlayoutInterval
		}
		group.nextPlayout = next
	}
}
