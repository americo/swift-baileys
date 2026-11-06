import Foundation

/// RTP header as WhatsApp frames it: fixed 12 bytes plus a `0xdebe` extension block, which is
/// empty for plain speech and carries one word for DTX or audio piggyback.
public struct CallRTPHeader: Equatable, Sendable {
	public static let fixedLength = 12
	public static let speechLength = 16
	public static let extensionProfile: UInt16 = 0xdebe
	public static let opusPayloadType: UInt8 = 120
	public static let rfc7587OpusPayloadType: UInt8 = 111

	static func isAudioPayloadType(_ payloadType: UInt8) -> Bool {
		payloadType == opusPayloadType || payloadType == rfc7587OpusPayloadType
	}

	public var marker: Bool
	public var payloadType: UInt8
	public var sequenceNumber: UInt16
	public var timestamp: UInt32
	public var ssrc: UInt32
	public var extensionWord: UInt32?

	public init(
		marker: Bool = false,
		payloadType: UInt8 = CallRTPHeader.opusPayloadType,
		sequenceNumber: UInt16,
		timestamp: UInt32,
		ssrc: UInt32,
		extensionWord: UInt32? = nil
	) {
		self.marker = marker
		self.payloadType = payloadType
		self.sequenceNumber = sequenceNumber
		self.timestamp = timestamp
		self.ssrc = ssrc
		self.extensionWord = extensionWord
	}

	public var encodedLength: Int {
		extensionWord == nil ? Self.speechLength : Self.speechLength + 4
	}

	public func encoded() -> Data {
		var bytes = [UInt8](repeating: 0, count: encodedLength)
		bytes[0] = 0x80 | 0x10
		bytes[1] = (marker ? 0x80 : 0) | (payloadType & 0x7f)
		put16(&bytes, 2, sequenceNumber)
		put32(&bytes, 4, timestamp)
		put32(&bytes, 8, ssrc)
		put16(&bytes, 12, Self.extensionProfile)
		bytes[15] = extensionWord == nil ? 0 : 1
		if let extensionWord {
			put32(&bytes, 16, extensionWord)
		}

		return Data(bytes)
	}

	/// Total header length (fixed part, CSRCs and extension block) of `packet`, if it is RTP v2.
	public static func length(of packet: Data) -> Int? {
		let bytes = [UInt8](packet)
		guard bytes.count >= fixedLength, bytes[0] >> 6 == 2 else {
			return nil
		}

		var length = fixedLength + Int(bytes[0] & 0x0f) * 4
		guard bytes.count >= length else {
			return nil
		}

		if bytes[0] & 0x10 != 0 {
			guard bytes.count >= length + 4 else {
				return nil
			}

			length += 4 + (Int(bytes[length + 2]) << 8 | Int(bytes[length + 3])) * 4
			guard bytes.count >= length else {
				return nil
			}
		}

		return length
	}

	/// Parses the fixed fields; the extension word is read when the block is exactly one word.
	public static func parse(_ packet: Data) -> CallRTPHeader? {
		guard let length = length(of: packet) else {
			return nil
		}

		let bytes = [UInt8](packet)
		var word: UInt32?
		if bytes[0] & 0x10 != 0, bytes[0] & 0x0f == 0, length == speechLength + 4,
		   UInt16(bytes[12]) << 8 | UInt16(bytes[13]) == extensionProfile {
			word = (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[16 + $1]) }
		}

		return CallRTPHeader(
			marker: bytes[1] & 0x80 != 0,
			payloadType: bytes[1] & 0x7f,
			sequenceNumber: UInt16(bytes[2]) << 8 | UInt16(bytes[3]),
			timestamp: (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[4 + $1]) },
			ssrc: (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[8 + $1]) },
			extensionWord: word
		)
	}

	private func put16(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt16) {
		bytes[offset] = UInt8(value >> 8)
		bytes[offset + 1] = UInt8(truncatingIfNeeded: value)
	}

	private func put32(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt32) {
		for index in 0..<4 {
			bytes[offset + index] = UInt8(truncatingIfNeeded: value >> UInt32(24 - 8 * index))
		}
	}
}

/// Protects outgoing audio and authenticates incoming audio for one 1:1 call: AES-CTR payload
/// encryption plus the truncated HMAC-SHA1 "WARP" tag, keyed per participant.
public struct CallAudioPipeline {
	public static let opusSamplesPerPacket16kHz60ms: UInt32 = 960

	public struct Received: Equatable, Sendable {
		public let header: CallRTPHeader
		public let payload: Data
	}

	public enum ReceiveError: Error, Equatable, Sendable {
		case malformed
		case authenticationFailed
		case replayed
	}

	private var sendKeys: CallSRTPKeys
	private var receiveKeys: CallSRTPKeys
	private let tagLength: Int
	private let ssrc: UInt32
	private let payloadType: UInt8
	private let samplesPerPacket: UInt32

	private var sequence: UInt16 = 1
	private var timestamp: UInt32 = 0
	private var sendROC: UInt32 = 0
	private var lastSentSequence: UInt16?
	private var receiveStreams: [UInt32: ReceiveStream] = [:]

	/// The RTP timestamp the next packet will carry, which is where this stream's clock stands.
	var nextTimestamp: UInt32 {
		timestamp
	}

	private static let maxReceiveStreams = 8

	/// - Parameters:
	///   - callKey: the 32-byte key exchanged in the offer.
	///   - selfParticipantID: our id; send keys derive from it.
	///   - peerParticipantID: the peer's id; receive keys derive from it.
	public init(
		callKey: Data,
		selfParticipantID: String,
		peerParticipantID: String,
		ssrc: UInt32,
		tagLength: Int = CallMediaCrypto.warpTagLength,
		payloadType: UInt8 = CallRTPHeader.opusPayloadType,
		samplesPerPacket: UInt32 = CallAudioPipeline.opusSamplesPerPacket16kHz60ms
	) throws {
		self.sendKeys = try CallMediaCrypto.deriveRTPKeys(
			callKey: callKey,
			participantID: CallMediaCrypto.formatParticipantID(selfParticipantID)
		)
		self.receiveKeys = try CallMediaCrypto.deriveRTPKeys(
			callKey: callKey,
			participantID: CallMediaCrypto.formatParticipantID(peerParticipantID)
		)
		self.tagLength = min(max(tagLength, 1), 20)
		self.ssrc = ssrc
		self.payloadType = payloadType
		self.samplesPerPacket = samplesPerPacket
	}

	/// Moves sending to a new group media key. Sequence numbers and the rollover counter carry on: it is
	/// the same stream, and only what protects it has changed.
	public mutating func rekeySend(callKey: Data, selfParticipantID: String) throws {
		sendKeys = try CallMediaCrypto.deriveRTPKeys(
			callKey: callKey,
			participantID: CallMediaCrypto.formatParticipantID(selfParticipantID)
		)
	}

	/// Moves receiving to a new group media key, keeping each stream's rollover state and replay window.
	public mutating func rekeyReceive(callKey: Data, peerParticipantID: String) throws {
		receiveKeys = try CallMediaCrypto.deriveRTPKeys(
			callKey: callKey,
			participantID: CallMediaCrypto.formatParticipantID(peerParticipantID)
		)
	}

	/// Wraps one Opus frame: header, encrypted payload, WARP tag.
	public mutating func protect(_ opusFrame: Data) throws -> Data {
		let header = CallRTPHeader(
			payloadType: payloadType,
			sequenceNumber: sequence,
			timestamp: timestamp,
			ssrc: ssrc
		)
		if let last = lastSentSequence, header.sequenceNumber < last {
			sendROC &+= 1
		}
		lastSentSequence = header.sequenceNumber
		sequence &+= 1
		timestamp &+= samplesPerPacket

		var packet = header.encoded()
		try packet.append(CallMediaCrypto.cryptPayload(
			opusFrame,
			keys: sendKeys,
			ssrc: header.ssrc,
			roc: sendROC,
			sequence: header.sequenceNumber
		))
		packet.append(CallMediaCrypto.warpTag(
			authKey: sendKeys.authKey,
			packetWithoutTag: packet,
			roc: sendROC,
			length: tagLength
		))
		return packet
	}

	/// Authenticates then decrypts one packet. State only advances for authenticated packets.
	public mutating func unprotect(_ packet: Data) throws -> Received {
		var (header, payload) = try CallSRTPReceive.unprotect(
			packet,
			keys: receiveKeys,
			tagLength: tagLength,
			streams: &receiveStreams,
			maxStreams: Self.maxReceiveStreams
		)
		if packet[packet.startIndex] & 0x20 != 0, let padding = payload.last, Int(padding) <= payload.count {
			payload.removeLast(Int(padding))
		}

		return Received(header: header, payload: payload)
	}

	/// Accepts an audio RTP packet that arrived inside an authenticated video packet, which is how a
	/// WhatsApp client sends its speech in a video call. It has no tag of its own, but runs through
	/// this stream's replay check like audio that arrives alone.
	public mutating func acceptCarried(_ packet: Data) -> Received? {
		guard let header = CallRTPHeader.parse(packet),
			  CallRTPHeader.isAudioPayloadType(header.payloadType),
			  let headerLength = CallRTPHeader.length(of: packet),
			  packet.count > headerLength else {
			return nil
		}

		var stream = receiveStreams[header.ssrc] ?? ReceiveStream()
		guard receiveStreams[header.ssrc] != nil || receiveStreams.count < Self.maxReceiveStreams,
			  let roc = stream.estimateROC(for: header.sequenceNumber),
			  stream.accept(sequence: header.sequenceNumber, roc: roc) else {
			return nil
		}

		receiveStreams[header.ssrc] = stream
		var payload = Data(packet.dropFirst(headerLength))
		if packet[packet.startIndex] & 0x20 != 0, let padding = payload.last, Int(padding) < payload.count {
			payload.removeLast(Int(padding))
		}

		return Received(header: header, payload: payload)
	}

	/// Rollover counter and replay window of one remote SSRC (RFC 3711 §3.3).
	struct ReceiveStream {
		private var roc: UInt32 = 0
		private var highest: UInt16?
		private var window: UInt64 = 0

		func estimateROC(for sequence: UInt16) -> UInt32? {
			guard let highest else {
				return roc
			}

			if highest < 0x8000 {
				if sequence > highest && sequence - highest > 0x8000 {
					return roc == 0 ? nil : roc - 1
				}
				return roc
			}

			if highest > 0x8000, sequence < highest - 0x8000 {
				return roc &+ 1
			}
			return roc
		}

		mutating func accept(sequence: UInt16, roc candidate: UInt32) -> Bool {
			let index = UInt64(candidate) << 16 | UInt64(sequence)
			guard let highest else {
				self.highest = sequence
				self.roc = candidate
				window = 1
				return true
			}

			let top = UInt64(roc) << 16 | UInt64(highest)
			if index > top {
				let shift = index - top
				window = shift >= 64 ? 1 : (window << shift) | 1
				self.highest = sequence
				self.roc = candidate
				return true
			}

			let age = top - index
			guard age < 64, window & (1 << age) == 0 else {
				return false
			}

			window |= 1 << age
			return true
		}
	}
}
