import Foundation

/// A datagram path to the call relay. `CallRelayTransport` is the real one; tests use a fake.
public protocol CallRelayLink: Sendable {
	/// Messages received from the relay: STUN, RTP and RTCP, one per element.
	var messages: AsyncStream<Data> { get }
	func open() async throws
	func send(_ message: Data) async throws
	func close() async
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

/// Media half of a 1:1 call: registers with the relay (STUN Allocate and keepalives), then turns
/// microphone frames into protected Opus RTP and encoded pictures into protected H.264 RTP, and
/// incoming RTP back into PCM and pictures.
///
/// Every call can carry video, since a voice call can be upgraded. Signaling is separate
/// (`startVoiceCall`, `acceptVoiceCall`); this takes the call key and relay block those produce.
public actor CallSession {
	public struct Configuration: Sendable {
		public let callID: String
		public let selfParticipantID: String
		public let peerParticipantID: String
		public let callKey: Data
		public let relay: CallRelayData

		public init(
			callID: String,
			selfParticipantID: String,
			peerParticipantID: String,
			callKey: Data,
			relay: CallRelayData
		) {
			self.callID = callID
			self.selfParticipantID = selfParticipantID
			self.peerParticipantID = peerParticipantID
			self.callKey = callKey
			self.relay = relay
		}
	}

	public static let allocateRetryInterval: Duration = .seconds(1)
	public static let allocateTimeout: Duration = .seconds(10)
	/// The Allocate is re-sent with a fresh ping at this cadence for the whole call: the relay takes
	/// it as consent to keep forwarding.
	public static let keepaliveInterval: Duration = .seconds(1)
	/// How long the peer can send nothing at all before the call is taken to be over. Official clients
	/// send RTCP every 1.5 s even while muted, so this is not silence on the line but a peer that is gone.
	public static let defaultPeerSilenceTimeout: Duration = .seconds(10)
	/// Cadence of the reports each side sends about the video it receives and sends.
	public static let reportInterval: Duration = .milliseconds(1500)
	/// How long the peer's keyframe is waited on before asking again.
	public static let peerKeyframeInterval: Duration = .seconds(1)
	/// Floor under an urgent request, such as a decoder that has just failed on every picture.
	public static let urgentPeerKeyframeInterval: Duration = .milliseconds(200)
	/// Where the encoder starts, and what the loss reports may move it between. Without a measure of
	/// the path, starting below the 2 Mbit/s official clients use costs less than starting above it.
	public static let initialVideoBitrate = 1_200_000
	public static let minimumVideoBitrate = 250_000
	public static let maximumVideoBitrate = 2_000_000

	/// How far above the measured video rate the pacer runs, the factor WebRTC's paced sender uses.
	private static let paceFactor = 2.5
	/// The pace before the call has a rate to go by, and the least it ever runs at.
	private static let paceFloorBps: Double = 4_000_000
	/// How much may leave at once: an ordinary frame goes through whole, while a keyframe is spread out.
	private static let paceBurst: Duration = .milliseconds(40)
	private static let paceWindow: Duration = .seconds(1)
	/// Sent packets kept to answer NACKs, longer than a NACK takes to come back over any path.
	private static let sentHistorySize = 512
	private static let maxResends = 2

	/// Decoded PCM frames (16 kHz mono) from the peer.
	public nonisolated let receivedAudio: AsyncStream<[Int16]>
	/// Pictures from the peer. Only the newest few wait: stale video is worse than a dropped frame.
	public nonisolated let receivedVideo: AsyncStream<CallVideoFrame>
	public nonisolated let videoSendEvents: AsyncStream<CallVideoSendEvent>
	/// Yields when the peer has stopped sending anything, or the relay path has closed. A hang-up does
	/// not always reach this client as a stanza, and without this the call would stay up on its own.
	public nonisolated let peerGone: AsyncStream<Void>

	private let receivedContinuation: AsyncStream<[Int16]>.Continuation
	private let receivedVideoContinuation: AsyncStream<CallVideoFrame>.Continuation
	private let videoSendEventsContinuation: AsyncStream<CallVideoSendEvent>.Continuation
	private let peerGoneContinuation: AsyncStream<Void>.Continuation
	private let peerSilenceTimeout: Duration
	private var lastPeerActivity: ContinuousClock.Instant?
	private var watchdogTask: Task<Void, Never>?
	private let configuration: Configuration
	private let link: any CallRelayLink
	private let relayToken: Data
	private let integrityKey: Data
	private let relayHost: String
	private let relayPort: UInt16
	private var pipeline: CallAudioPipeline
	private var video: CallVideoPipeline
	private let rtcpSendKeys: CallSRTPKeys
	private let rtcpReceiveKeys: CallSRTPKeys
	private let cname: [UInt8]
	private var rtcpIndex: UInt32 = 1
	private var rtcpReplay = CallSRTCPReplayWindow()
	private var reception = CallRTPReceptionStats()
	private let encoder: CallOpusEncoder
	private let decoder: CallOpusDecoder
	private let allocateRequest: Data
	private let allocateTransactionID: Data

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
	}

	/// Connects to the relay and waits for the Allocate to succeed.
	public func start() async throws {
		guard !isRunning else {
			return
		}

		try await link.open()
		isRunning = true
		WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): relay channel open \(self.relayHost, privacy: .public):\(self.relayPort)")

		let messages = link.messages
		receiveTask = Task { [weak self] in
			for await message in messages {
				await self?.handle(message)
			}
			await self?.relayEnded()
		}

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
			}
		}
		if isSendingVideo {
			requireKeyframe()
		}
	}

	/// Encodes and sends one 60 ms microphone frame (960 samples at 16 kHz).
	public func sendAudio(_ samples: [Int16]) async throws {
		guard isRunning, isAllocated else {
			throw CallSessionError.notRunning
		}

		let opus = try encoder.encode(samples)
		let packet = try pipeline.protect(opus)
		try await link.send(packet)
		framesSent += 1
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
		guard isRunning, isAllocated else {
			throw CallSessionError.notRunning
		}
		guard isSendingVideo else {
			return
		}

		let isIDR = CallH264.hasIDR(accessUnit)
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
			guard isRunning, isSendingVideo else {
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

		WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): stopped sent=\(self.framesSent) received=\(self.framesReceived) rejected=\(self.packetsRejected) badKeys=\(self.keysRejected) undecodable=\(self.decodeFailures) decodedPeak=\(self.decodedPeak) carried=\(self.carriedAudioPackets) videoSent=\(self.videoFramesSent) videoReceived=\(self.videoFramesReceived) videoLost=\(self.videoPacketsLost) videoRejected=\(self.videoPacketsRejected) resent=\(self.videoPacketsResent) keyframesAsked=\(self.keyframesRequestedByPeer)/\(self.keyframesRequestedFromPeer) bitrate=\(self.videoBitrate)")
		isRunning = false
		isAllocated = false
		keepaliveTask?.cancel()
		receiveTask?.cancel()
		reportTask?.cancel()
		watchdogTask?.cancel()
		keepaliveTask = nil
		receiveTask = nil
		reportTask = nil
		watchdogTask = nil
		await link.close()
		receivedContinuation.finish()
		receivedVideoContinuation.finish()
		videoSendEventsContinuation.finish()
		peerGoneContinuation.finish()
	}

	// MARK: Receiving

	private func handle(_ message: Data) async {
		guard isRunning, let first = message.first else {
			return
		}

		if first & 0xc0 == 0 {
			handleSTUN(message)
		} else if first >> 6 == 2 {
			// RTP and RTCP share the path. RFC 5761 keeps their payload types from overlapping.
			if message.count > 1, (192...223).contains(message[message.startIndex + 1]) {
				await handleRTCP(message)
			} else {
				await handleRTP(message)
			}
		}
	}

	private func handleSTUN(_ message: Data) {
		if CallSTUN.isAllocateOrBindingSuccess(message) {
			isAllocated = true
		} else if CallSTUN.isAllocateError(message) {
			allocateError = .some(CallSTUN.errorCode(message))
		}
	}

	/// Audio and video share keys but have separate SSRCs and rollover counters, so packets are told
	/// apart by payload type before anything is verified.
	private func handleRTP(_ message: Data) async {
		guard let header = CallRTPHeader.parse(message) else {
			packetsRejected += 1
			return
		}

		if header.payloadType == CallVideoRTPHeader.h264PayloadType {
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
		guard message.count >= 8 else {
			return
		}

		let bytes = [UInt8](message.prefix(8))
		let sender = (4..<8).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[$1]) }
		guard let (plain, index) = CallMediaCrypto.unprotectRTCP(message, keys: rtcpReceiveKeys, senderSSRC: sender),
			  rtcpReplay.accept(sender: sender, index: index),
			  let summary = CallRTCP.parse(plain) else {
			return
		}

		lastPeerActivity = clock.now
		for timing in summary.senderTimings {
			reception.observeSenderReport(ssrc: timing.ssrc, compactNTP: timing.compactNTP, arrivalMs: monotonicMs())
		}
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
		} else {
			cleanReports += 1
			if cleanReports >= 3 {
				next = Int(Double(videoBitrate) * 1.08)
				cleanReports = 0
			}
		}

		next = min(max(next, Self.minimumVideoBitrate), Self.maximumVideoBitrate)
		guard next != videoBitrate else {
			return
		}

		videoBitrate = next
		videoSendEventsContinuation.yield(.targetBitrate(next))
	}

	/// The periodic report, once video flows in either direction. It also retries a keyframe request
	/// the throttle held back.
	private func sendVideoReport() async {
		guard isRunning, isAllocated, isSendingVideo || video.inboundSSRC != nil else {
			return
		}

		if peerKeyframePending, peerKeyframeAskedAt.map({ $0.duration(to: clock.now) >= Self.peerKeyframeInterval }) ?? true {
			await requestPeerKeyframe()
		}

		// The media clock at this instant, read from the newest picture's capture: pairing a send time
		// with a capture-stamped timestamp would tell the peer every picture was taken later than it was.
		var timestamp = lastVideoTimestamp
		if let anchor = videoClockAnchor {
			let (seconds, attoseconds) = anchor.at.duration(to: clock.now).components
			let ticks = Double(seconds) * Double(CallVideoRTPHeader.clockRate)
				+ Double(attoseconds) * 1e-18 * Double(CallVideoRTPHeader.clockRate)
			timestamp = anchor.timestamp &+ UInt32(truncatingIfNeeded: Int64(ticks))
		}
		await sendRTCP(CallRTCP.senderReport(
			ssrc: video.ssrc,
			rtpTimestamp: timestamp,
			packetsSent: videoPacketsSent,
			octetsSent: videoOctetsSent,
			wallclockMs: UInt64(Date().timeIntervalSince1970 * 1000),
			cname: cname,
			report: reception.report(nowMs: monotonicMs())
		))
	}

	private func sendRTCP(_ plain: Data) async {
		guard let protected = try? CallMediaCrypto.protectRTCP(
			plain,
			keys: rtcpSendKeys,
			senderSSRC: video.ssrc,
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

	private func relayEnded() async {
		guard isRunning else {
			return
		}

		WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): relay path closed")
		peerGoneContinuation.yield()
		await stop()
	}

	/// Only authenticated traffic counts, so nothing but the peer can keep a call alive. A call that
	/// has not heard from the peer yet waits, since media can take a moment to start.
	private func checkPeerActivity() {
		guard isRunning, let last = lastPeerActivity, last.duration(to: clock.now) >= peerSilenceTimeout else {
			return
		}

		WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): nothing from the peer for \(self.peerSilenceTimeout, privacy: .public)")
		lastPeerActivity = nil
		peerGoneContinuation.yield()
	}
}
