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

/// Media half of a 1:1 voice call: registers with the relay (STUN Allocate and keepalives), then
/// turns microphone frames into protected Opus RTP and incoming RTP back into PCM.
///
/// Signaling is separate (`startVoiceCall`, `acceptVoiceCall`); this takes the call key and relay
/// block those produce.
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

	/// Decoded PCM frames (16 kHz mono) from the peer.
	public nonisolated let receivedAudio: AsyncStream<[Int16]>

	private let receivedContinuation: AsyncStream<[Int16]>.Continuation
	private let configuration: Configuration
	private let link: any CallRelayLink
	private let relayToken: Data
	private let integrityKey: Data
	private let relayHost: String
	private let relayPort: UInt16
	private var pipeline: CallAudioPipeline
	private let encoder: CallOpusEncoder
	private let decoder: CallOpusDecoder
	private let allocateRequest: Data
	private let allocateTransactionID: Data

	private var isRunning = false
	private var isAllocated = false
	private var allocateError: Int??
	private var receiveTask: Task<Void, Never>?
	private var keepaliveTask: Task<Void, Never>?

	public private(set) var framesSent = 0
	public private(set) var framesReceived = 0
	public private(set) var packetsRejected = 0
	public private(set) var decodeFailures = 0
	public private(set) var keysRejected = 0
	/// Loudest decoded sample so far. Zero with packets arriving means the peer's audio decodes to silence.
	public private(set) var decodedPeak = 0

	/// Builds a session. `link` defaults to the DTLS+SCTP transport to the relay the call selected.
	public init(configuration: Configuration, link: (any CallRelayLink)? = nil) throws {
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
		let transaction = try CallKeyMessage.generateCallKey().prefix(12)

		self.configuration = configuration
		self.relayToken = configuration.relay.relayTokens[endpoint.tokenID]
		self.integrityKey = key
		self.relayHost = address.host
		self.relayPort = address.port
		self.link = link ?? CallRelayTransport(host: address.host, port: address.port)
		self.pipeline = try CallAudioPipeline(
			callKey: configuration.callKey,
			selfParticipantID: configuration.selfParticipantID,
			peerParticipantID: configuration.peerParticipantID,
			ssrc: ssrc,
			tagLength: configuration.relay.warpTagLength ?? CallMediaCrypto.warpTagLength
		)
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

	public func stop() async {
		guard isRunning || receiveTask != nil else {
			return
		}

		WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): stopped sent=\(self.framesSent) received=\(self.framesReceived) rejected=\(self.packetsRejected) badKeys=\(self.keysRejected) undecodable=\(self.decodeFailures) decodedPeak=\(self.decodedPeak)")
		isRunning = false
		isAllocated = false
		keepaliveTask?.cancel()
		receiveTask?.cancel()
		keepaliveTask = nil
		receiveTask = nil
		await link.close()
		receivedContinuation.finish()
	}

	// MARK: Receiving

	private func handle(_ message: Data) {
		guard isRunning, let first = message.first else {
			return
		}

		if first & 0xc0 == 0 {
			handleSTUN(message)
		} else if first >> 6 == 2 {
			handleRTP(message)
		}
	}

	private func handleSTUN(_ message: Data) {
		if CallSTUN.isAllocateOrBindingSuccess(message) {
			isAllocated = true
		} else if CallSTUN.isAllocateError(message) {
			allocateError = .some(CallSTUN.errorCode(message))
		}
	}

	private func handleRTP(_ message: Data) {
		// RTCP (payload types 200-204) is not authenticated or interpreted yet.
		if message.count > 1, (192...223).contains(message[message.startIndex + 1]) {
			return
		}

		var received: CallAudioPipeline.Received?
		do {
			received = try pipeline.unprotect(message)
			let pcm = try decoder.decode(received?.payload ?? Data())
			framesReceived += 1
			for sample in pcm {
				decodedPeak = max(decodedPeak, abs(Int(sample)))
			}
			receivedContinuation.yield(pcm)
		} catch CallAudioPipeline.ReceiveError.authenticationFailed {
			packetsRejected += 1
			keysRejected += 1
		} catch is CallAudioPipeline.ReceiveError {
			packetsRejected += 1
		} catch {
			packetsRejected += 1
			decodeFailures += 1
			if decodeFailures <= 5, let received {
				let first = received.payload.first.map { String(format: "%02x", $0) } ?? "-"
				WhatsAppLog.logger.notice("call \(self.configuration.callID, privacy: .public): undecodable packet pt=\(received.header.payloadType) bytes=\(received.payload.count) first=\(first, privacy: .public)")
			}
		}
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

		await stop()
	}
}
