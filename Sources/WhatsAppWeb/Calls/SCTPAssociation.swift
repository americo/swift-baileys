import Foundation

/// A minimal, sans-IO SCTP association (RFC 4960) carrying one unordered, partially reliable
/// stream, which is what the WhatsApp call relay expects on top of DTLS.
///
/// The type owns no socket and reads no clock: the caller feeds it packets and a millisecond
/// timestamp, then drains `pollTransmit()` and `pollEvent()`. Media chunks are never retransmitted:
/// a chunk that is not acknowledged within `retransmissionTimeoutMs` is abandoned and the peer is
/// told to skip it with FORWARD-TSN (RFC 3758), so a lost packet cannot block the ones behind it.
public struct SCTPAssociation {
	public enum Role: Sendable {
		case client
		case server
	}

	public enum State: Equatable, Sendable {
		case closed
		case cookieWait
		case cookieEchoed
		case established
	}

	public enum Event: Equatable, Sendable {
		case established
		case message(streamID: UInt16, ppid: UInt32, data: Data)
		case closed(String)
	}

	public enum SendError: Error, Equatable, Sendable {
		case notEstablished
	}

	/// How the path to the peer is coping, since the last time this was read.
	public struct SendPressure: Equatable, Sendable {
		/// Chunks sent.
		public var sent = 0
		/// Chunks given up on, unacknowledged after `retransmissionTimeoutMs`.
		public var abandoned = 0
		/// How long the newest acknowledged chunk took, in milliseconds.
		public var ackDelayMs: UInt64?

		public init(sent: Int = 0, abandoned: Int = 0, ackDelayMs: UInt64? = nil) {
			self.sent = sent
			self.abandoned = abandoned
			self.ackDelayMs = ackDelayMs
		}
	}

	// MARK: Constants

	public static let defaultPort: UInt16 = 5000
	public static let ppidBinary: UInt32 = 53
	public static let ppidBinaryEmpty: UInt32 = 57
	public static let ppidStringEmpty: UInt32 = 56
	public static let retransmissionTimeoutMs: UInt64 = 300

	private static let maxPayload = 1160
	private static let advertisedWindow: UInt32 = 1_048_576
	private static let handshakeIntervalMs: UInt64 = 1000
	private static let handshakeMaxRetries = 8

	private enum ChunkType {
		static let reconfig: UInt8 = 130
		static let data: UInt8 = 0
		static let initiate: UInt8 = 1
		static let initiateAck: UInt8 = 2
		static let sack: UInt8 = 3
		static let heartbeat: UInt8 = 4
		static let heartbeatAck: UInt8 = 5
		static let abort: UInt8 = 6
		static let shutdown: UInt8 = 7
		static let shutdownAck: UInt8 = 8
		static let cookieEcho: UInt8 = 10
		static let cookieAck: UInt8 = 11
		static let shutdownComplete: UInt8 = 14
		static let forwardTSN: UInt8 = 192
	}

	private enum Parameter {
		static let stateCookie: UInt16 = 7
		static let supportedExtensions: UInt16 = 0x8008
		static let forwardTSNSupported: UInt16 = 0xc000
	}

	private struct Outstanding {
		var chunk: [UInt8]
		var sentAt: UInt64
	}

	private struct Fragment {
		let beginning: Bool
		let end: Bool
		let streamID: UInt16
		let ppid: UInt32
		let payload: [UInt8]
	}

	// MARK: State

	public let role: Role
	public private(set) var state: State = .closed

	private let localPort: UInt16
	private let remotePort: UInt16
	private var random: () -> UInt32

	private var localTag: UInt32 = 0
	private var peerTag: UInt32 = 0
	private var peerSupportsForwardTSN = false

	private var nextTSN: UInt32 = 0
	private var streamSequence: [UInt16: UInt16] = [:]
	private var outstanding: [UInt32: Outstanding] = [:]
	/// Highest TSN the peer is known to have passed, by SACK or by our FORWARD-TSN.
	private var peerAckPoint: UInt32 = 0

	private var cumulativeTSN: UInt32 = 0
	private var receivedAboveCumulative: Set<UInt32> = []
	private var fragments: [UInt32: Fragment] = [:]

	private var outbox: [Data] = []
	private var events: [Event] = []
	private var pressure = SendPressure()

	private var handshakePacket: Data?
	private var handshakeDeadline: UInt64?
	private var handshakeRetries = 0

	public init(
		role: Role,
		localPort: UInt16 = SCTPAssociation.defaultPort,
		remotePort: UInt16 = SCTPAssociation.defaultPort,
		random: @escaping () -> UInt32 = { UInt32.random(in: 1...UInt32.max) }
	) {
		self.role = role
		self.localPort = localPort
		self.remotePort = remotePort
		self.random = random
	}

	// MARK: Driving

	/// Starts the handshake on a client by queueing INIT.
	public mutating func connect(now: UInt64) {
		guard role == .client, state == .closed else {
			return
		}

		localTag = nonZeroRandom()
		nextTSN = random()
		var value = [UInt8]()
		value += be32(localTag)
		value += be32(Self.advertisedWindow)
		value += be16(0xffff) + be16(0xffff)
		value += be32(nextTSN)
		// The extensions the WebRTC stack that interoperates with the relay announces.
		value += parameter(Parameter.supportedExtensions, [ChunkType.reconfig, ChunkType.forwardTSN])
		let packet = makePacket(verificationTag: 0, chunks: [chunk(ChunkType.initiate, 0, value)])
		state = .cookieWait
		startHandshakeTimer(packet, now: now)
		outbox.append(packet)
	}

	public mutating func pollTransmit() -> Data? {
		outbox.isEmpty ? nil : outbox.removeFirst()
	}

	public mutating func pollEvent() -> Event? {
		events.isEmpty ? nil : events.removeFirst()
	}

	/// Hands back what the send path has seen since the previous call.
	public mutating func takeSendPressure() -> SendPressure {
		defer { pressure = SendPressure() }
		return pressure
	}

	/// The next millisecond timestamp at which `handleTimeout` should be called.
	public func pollTimeout() -> UInt64? {
		var deadline = handshakeDeadline
		if let oldest = outstanding.values.map(\.sentAt).min() {
			let due = oldest + Self.retransmissionTimeoutMs
			deadline = deadline.map { min($0, due) } ?? due
		}

		return deadline
	}

	public mutating func handleTimeout(now: UInt64) {
		if let deadline = handshakeDeadline, now >= deadline, let packet = handshakePacket {
			handshakeRetries += 1
			if handshakeRetries > Self.handshakeMaxRetries {
				fail("handshake timed out")
				return
			}

			outbox.append(packet)
			handshakeDeadline = now + Self.handshakeIntervalMs << UInt64(min(handshakeRetries, 3))
		}

		guard state == .established else {
			return
		}

		let expired = outstanding.filter { now >= $0.value.sentAt + Self.retransmissionTimeoutMs }.map(\.key)
		guard !expired.isEmpty else {
			return
		}

		if peerSupportsForwardTSN {
			pressure.abandoned += expired.count
			expired.forEach { outstanding.removeValue(forKey: $0) }
			advancePeerAckPoint()
		} else {
			for tsn in expired {
				guard var entry = outstanding[tsn] else {
					continue
				}

				entry.sentAt = now
				outstanding[tsn] = entry
				outbox.append(makePacket(verificationTag: peerTag, chunks: [entry.chunk]))
			}
		}
	}

	/// Sends one message. Messages larger than a packet are fragmented.
	public mutating func send(
		_ message: Data,
		streamID: UInt16 = 0,
		ppid: UInt32 = SCTPAssociation.ppidBinary,
		unordered: Bool = true,
		now: UInt64
	) throws {
		guard state == .established else {
			throw SendError.notEstablished
		}

		// SCTP cannot carry an empty message, so it travels as one zero byte under its own PPID.
		let bytes = message.isEmpty ? [0] : [UInt8](message)
		let payloadPPID = message.isEmpty ? Self.ppidBinaryEmpty : ppid
		let pieces = stride(from: 0, to: bytes.count, by: Self.maxPayload).map {
			Array(bytes[$0..<min($0 + Self.maxPayload, bytes.count)])
		}

		let sequence = streamSequence[streamID, default: 0]
		if !unordered {
			streamSequence[streamID] = sequence &+ 1
		}

		for (index, piece) in pieces.enumerated() {
			var flags: UInt8 = 0
			if unordered { flags |= 0x04 }
			if index == 0 { flags |= 0x02 }
			if index == pieces.count - 1 { flags |= 0x01 }

			let tsn = nextTSN
			nextTSN &+= 1
			var value = be32(tsn) + be16(streamID) + be16(unordered ? 0 : sequence) + be32(payloadPPID)
			value += piece
			let dataChunk = chunk(ChunkType.data, flags, value)
			outstanding[tsn] = Outstanding(chunk: dataChunk, sentAt: now)
			pressure.sent += 1
			outbox.append(makePacket(verificationTag: peerTag, chunks: [dataChunk]))
		}
	}

	/// Aborts the association.
	public mutating func close() {
		guard state != .closed else {
			return
		}

		if peerTag != 0 {
			outbox.append(makePacket(verificationTag: peerTag, chunks: [chunk(ChunkType.abort, 0, [])]))
		}
		state = .closed
		handshakeDeadline = nil
		handshakePacket = nil
		outstanding.removeAll()
	}

	// MARK: Receiving

	public mutating func receive(_ packet: Data, now: UInt64) {
		let bytes = [UInt8](packet)
		guard bytes.count >= 12, Self.checksumIsValid(bytes) else {
			return
		}

		let verificationTag = read32(bytes, 4)
		let chunks = parseChunks(bytes)
		guard let first = chunks.first else {
			return
		}

		if first.type == ChunkType.initiate {
			guard verificationTag == 0 else {
				return
			}
		} else if verificationTag != localTag {
			return
		}

		var needsSACK = false
		for chunk in chunks {
			switch chunk.type {
			case ChunkType.initiate:
				handleInit(chunk.value)
			case ChunkType.initiateAck:
				handleInitAck(chunk.value, now: now)
			case ChunkType.cookieEcho:
				handleCookieEcho(chunk.value)
			case ChunkType.cookieAck:
				if state == .cookieEchoed {
					state = .established
					clearHandshakeTimer()
					peerAckPoint = nextTSN &- 1
					events.append(.established)
				}
			case ChunkType.data:
				if state == .established {
					handleData(chunk)
					needsSACK = true
				}
			case ChunkType.sack:
				handleSACK(chunk.value, now: now)
			case ChunkType.forwardTSN:
				if state == .established {
					handleForwardTSN(chunk.value)
					needsSACK = true
				}
			case ChunkType.heartbeat:
				outbox.append(makePacket(verificationTag: peerTag, chunks: [
					self.chunk(ChunkType.heartbeatAck, 0, chunk.value)
				]))
			case ChunkType.abort:
				fail("peer aborted the association")
				return
			case ChunkType.shutdown:
				outbox.append(makePacket(verificationTag: peerTag, chunks: [self.chunk(ChunkType.shutdownAck, 0, [])]))
			case ChunkType.shutdownAck:
				outbox.append(makePacket(verificationTag: peerTag, chunks: [self.chunk(ChunkType.shutdownComplete, 0, [])]))
				fail("peer shut the association down")
				return
			default:
				break
			}
		}

		if needsSACK {
			outbox.append(makePacket(verificationTag: peerTag, chunks: [makeSACK()]))
		}
	}

	// MARK: Handshake handling

	private mutating func handleInit(_ value: [UInt8]) {
		guard role == .server, value.count >= 16 else {
			return
		}

		let peerInitiateTag = read32(value, 0)
		let peerWindow = read32(value, 4)
		let peerInitialTSN = read32(value, 12)
		let forward = advertisesForwardTSN(parameters(value, from: 16))
		guard peerInitiateTag != 0 else {
			return
		}

		let tag = state == .closed && localTag == 0 ? nonZeroRandom() : localTag
		localTag = tag
		let initialTSN = nextTSN == 0 ? random() : nextTSN
		nextTSN = initialTSN
		// Stateless cookie: everything needed to finish the handshake, echoed back by the client.
		let cookie = be32(peerInitiateTag) + be32(peerInitialTSN) + be32(peerWindow)
			+ be32(tag) + be32(initialTSN) + be32(forward ? 1 : 0)
		var reply = be32(tag) + be32(Self.advertisedWindow) + be16(0xffff) + be16(0xffff) + be32(initialTSN)
		reply += parameter(Parameter.stateCookie, cookie)
		reply += parameter(Parameter.supportedExtensions, [ChunkType.reconfig, ChunkType.forwardTSN])
		outbox.append(makePacket(
			verificationTag: peerInitiateTag,
			chunks: [chunk(ChunkType.initiateAck, 0, reply)]
		))
	}

	private mutating func handleInitAck(_ value: [UInt8], now: UInt64) {
		guard role == .client, state == .cookieWait, value.count >= 16 else {
			return
		}

		let params = parameters(value, from: 16)
		guard let cookie = params.first(where: { $0.type == Parameter.stateCookie })?.value else {
			return
		}

		peerTag = read32(value, 0)
		cumulativeTSN = read32(value, 12) &- 1
		peerSupportsForwardTSN = advertisesForwardTSN(params)
		let packet = makePacket(verificationTag: peerTag, chunks: [chunk(ChunkType.cookieEcho, 0, cookie)])
		state = .cookieEchoed
		startHandshakeTimer(packet, now: now)
		outbox.append(packet)
	}

	/// A peer announces FORWARD-TSN either with its own parameter or in the extension list.
	private func advertisesForwardTSN(_ params: [(type: UInt16, value: [UInt8])]) -> Bool {
		params.contains { parameter in
			parameter.type == Parameter.forwardTSNSupported
				|| (parameter.type == Parameter.supportedExtensions && parameter.value.contains(ChunkType.forwardTSN))
		}
	}

	private mutating func handleCookieEcho(_ value: [UInt8]) {
		guard role == .server, value.count >= 24 else {
			return
		}

		let echoedLocalTag = read32(value, 12)
		guard echoedLocalTag == localTag, state != .established else {
			if state == .established {
				outbox.append(makePacket(verificationTag: peerTag, chunks: [chunk(ChunkType.cookieAck, 0, [])]))
			}
			return
		}

		peerTag = read32(value, 0)
		cumulativeTSN = read32(value, 4) &- 1
		nextTSN = read32(value, 16)
		peerSupportsForwardTSN = read32(value, 20) == 1
		peerAckPoint = nextTSN &- 1
		state = .established
		outbox.append(makePacket(verificationTag: peerTag, chunks: [chunk(ChunkType.cookieAck, 0, [])]))
		events.append(.established)
	}

	// MARK: Data handling

	private mutating func handleData(_ chunk: (type: UInt8, flags: UInt8, value: [UInt8])) {
		guard chunk.value.count >= 12 else {
			return
		}

		let tsn = read32(chunk.value, 0)
		guard Self.serialGreater(tsn, cumulativeTSN), !receivedAboveCumulative.contains(tsn) else {
			return
		}

		let fragment = Fragment(
			beginning: chunk.flags & 0x02 != 0,
			end: chunk.flags & 0x01 != 0,
			streamID: read16(chunk.value, 4),
			ppid: read32(chunk.value, 8),
			payload: Array(chunk.value[12...])
		)
		receivedAboveCumulative.insert(tsn)
		advanceCumulative()

		if fragment.beginning && fragment.end {
			deliver(fragment.streamID, fragment.ppid, fragment.payload)
		} else {
			fragments[tsn] = fragment
			reassemble(around: tsn)
		}
	}

	private mutating func deliver(_ streamID: UInt16, _ ppid: UInt32, _ payload: [UInt8]) {
		let empty = ppid == Self.ppidBinaryEmpty || ppid == Self.ppidStringEmpty
		events.append(.message(streamID: streamID, ppid: ppid, data: empty ? Data() : Data(payload)))
	}

	/// Looks for a complete run of consecutive fragments containing `tsn`.
	private mutating func reassemble(around tsn: UInt32) {
		var start = tsn
		while let fragment = fragments[start], !fragment.beginning {
			let previous = start &- 1
			guard fragments[previous] != nil else {
				return
			}

			start = previous
		}
		guard fragments[start]?.beginning == true else {
			return
		}

		var parts = [UInt8]()
		var current = start
		while let fragment = fragments[current] {
			parts += fragment.payload
			if fragment.end {
				let first = fragments[start]!
				var cleanup = start
				while true {
					fragments.removeValue(forKey: cleanup)
					if cleanup == current { break }
					cleanup &+= 1
				}

				deliver(first.streamID, first.ppid, parts)
				return
			}

			current &+= 1
		}
	}

	private mutating func advanceCumulative() {
		while receivedAboveCumulative.contains(cumulativeTSN &+ 1) {
			cumulativeTSN &+= 1
			receivedAboveCumulative.remove(cumulativeTSN)
		}
	}

	private mutating func handleForwardTSN(_ value: [UInt8]) {
		guard value.count >= 4 else {
			return
		}

		let newCumulative = read32(value, 0)
		guard Self.serialGreater(newCumulative, cumulativeTSN) else {
			return
		}

		cumulativeTSN = newCumulative
		receivedAboveCumulative = receivedAboveCumulative.filter { Self.serialGreater($0, newCumulative) }
		fragments = fragments.filter { Self.serialGreater($0.key, newCumulative) }
		advanceCumulative()
	}

	private func makeSACK() -> [UInt8] {
		let ordered = receivedAboveCumulative.sorted { Self.serialGreater($1, $0) }
		var gaps = [(UInt16, UInt16)]()
		for tsn in ordered {
			let offset = UInt16(truncatingIfNeeded: tsn &- cumulativeTSN)
			if let last = gaps.last, last.1 &+ 1 == offset {
				gaps[gaps.count - 1].1 = offset
			} else {
				gaps.append((offset, offset))
			}
		}

		var value = be32(cumulativeTSN) + be32(Self.advertisedWindow) + be16(UInt16(gaps.count)) + be16(0)
		for gap in gaps {
			value += be16(gap.0) + be16(gap.1)
		}

		return chunk(ChunkType.sack, 0, value)
	}

	private mutating func handleSACK(_ value: [UInt8], now: UInt64) {
		guard state == .established, value.count >= 12 else {
			return
		}

		let cumulative = read32(value, 0)
		if let newest = outstanding.filter({ !Self.serialGreater($0.key, cumulative) }).values.map(\.sentAt).max() {
			pressure.ackDelayMs = now >= newest ? now - newest : 0
		}
		outstanding = outstanding.filter { Self.serialGreater($0.key, cumulative) }
		if Self.serialGreater(cumulative, peerAckPoint) {
			peerAckPoint = cumulative
		}

		let gapCount = Int(read16(value, 8))
		for index in 0..<gapCount where 12 + index * 4 + 4 <= value.count {
			let start = UInt32(read16(value, 12 + index * 4))
			let end = UInt32(read16(value, 14 + index * 4))
			guard start <= end else {
				continue
			}

			for offset in start...end {
				if let acked = outstanding.removeValue(forKey: cumulative &+ offset) {
					pressure.ackDelayMs = now >= acked.sentAt ? now - acked.sentAt : 0
				}
			}
		}
	}

	/// Moves the acknowledged point over chunks that are acked or abandoned, and tells the peer.
	private mutating func advancePeerAckPoint() {
		var point = peerAckPoint
		while Self.serialGreater(nextTSN, point &+ 1), outstanding[point &+ 1] == nil {
			point &+= 1
		}

		guard Self.serialGreater(point, peerAckPoint) else {
			return
		}

		peerAckPoint = point
		outbox.append(makePacket(verificationTag: peerTag, chunks: [chunk(ChunkType.forwardTSN, 0, be32(point))]))
	}

	// MARK: Timers and failure

	private mutating func startHandshakeTimer(_ packet: Data, now: UInt64) {
		handshakePacket = packet
		handshakeRetries = 0
		handshakeDeadline = now + Self.handshakeIntervalMs
	}

	private mutating func clearHandshakeTimer() {
		handshakePacket = nil
		handshakeDeadline = nil
		handshakeRetries = 0
	}

	private mutating func fail(_ reason: String) {
		state = .closed
		clearHandshakeTimer()
		outstanding.removeAll()
		events.append(.closed(reason))
	}

	private mutating func nonZeroRandom() -> UInt32 {
		var value = random()
		while value == 0 {
			value = random()
		}

		return value
	}

	// MARK: Wire format

	private func makePacket(verificationTag: UInt32, chunks: [[UInt8]]) -> Data {
		var bytes = be16(localPort) + be16(remotePort) + be32(verificationTag) + be32(0)
		chunks.forEach { bytes += $0 }
		let checksum = Self.crc32c(bytes)
		bytes[8] = UInt8(truncatingIfNeeded: checksum)
		bytes[9] = UInt8(truncatingIfNeeded: checksum >> 8)
		bytes[10] = UInt8(truncatingIfNeeded: checksum >> 16)
		bytes[11] = UInt8(truncatingIfNeeded: checksum >> 24)
		return Data(bytes)
	}

	private func chunk(_ type: UInt8, _ flags: UInt8, _ value: [UInt8]) -> [UInt8] {
		var bytes = [type, flags] + be16(UInt16(value.count + 4)) + value
		bytes += [UInt8](repeating: 0, count: (4 - bytes.count % 4) % 4)
		return bytes
	}

	private func parameter(_ type: UInt16, _ value: [UInt8]) -> [UInt8] {
		var bytes = be16(type) + be16(UInt16(value.count + 4)) + value
		bytes += [UInt8](repeating: 0, count: (4 - bytes.count % 4) % 4)
		return bytes
	}

	private func parseChunks(_ bytes: [UInt8]) -> [(type: UInt8, flags: UInt8, value: [UInt8])] {
		var result = [(type: UInt8, flags: UInt8, value: [UInt8])]()
		var offset = 12
		while offset + 4 <= bytes.count {
			let length = Int(read16(bytes, offset + 2))
			guard length >= 4, offset + length <= bytes.count else {
				break
			}

			result.append((bytes[offset], bytes[offset + 1], Array(bytes[(offset + 4)..<(offset + length)])))
			offset += length + (4 - length % 4) % 4
		}

		return result
	}

	private func parameters(_ bytes: [UInt8], from start: Int) -> [(type: UInt16, value: [UInt8])] {
		var result = [(type: UInt16, value: [UInt8])]()
		var offset = start
		while offset + 4 <= bytes.count {
			let length = Int(read16(bytes, offset + 2))
			guard length >= 4, offset + length <= bytes.count else {
				break
			}

			result.append((read16(bytes, offset), Array(bytes[(offset + 4)..<(offset + length)])))
			offset += length + (4 - length % 4) % 4
		}

		return result
	}

	private func be16(_ value: UInt16) -> [UInt8] {
		[UInt8(value >> 8), UInt8(truncatingIfNeeded: value)]
	}

	private func be32(_ value: UInt32) -> [UInt8] {
		(0..<4).map { UInt8(truncatingIfNeeded: value >> UInt32(24 - 8 * $0)) }
	}

	private func read16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
		UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
	}

	private func read32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
		(0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[offset + $1]) }
	}

	/// RFC 1982 serial number comparison: `lhs` is after `rhs`.
	static func serialGreater(_ lhs: UInt32, _ rhs: UInt32) -> Bool {
		lhs != rhs && lhs &- rhs < 0x8000_0000
	}

	// MARK: CRC32c

	private static let crcTable: [UInt32] = (0..<256).map { index in
		var crc = UInt32(index)
		for _ in 0..<8 {
			crc = crc & 1 == 1 ? (crc >> 1) ^ 0x82f6_3b78 : crc >> 1
		}

		return crc
	}

	static func crc32c(_ bytes: [UInt8]) -> UInt32 {
		var crc: UInt32 = 0xffff_ffff
		for byte in bytes {
			crc = crcTable[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
		}

		return ~crc
	}

	static func checksumIsValid(_ bytes: [UInt8]) -> Bool {
		guard bytes.count >= 12 else {
			return false
		}

		let stored = UInt32(bytes[8]) | UInt32(bytes[9]) << 8 | UInt32(bytes[10]) << 16 | UInt32(bytes[11]) << 24
		var zeroed = bytes
		zeroed.replaceSubrange(8..<12, with: [0, 0, 0, 0])
		return crc32c(zeroed) == stored
	}
}
