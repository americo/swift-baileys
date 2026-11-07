import Foundation

/// The 28-byte RTP header of WhatsApp's video sender: the fixed 12 bytes, then a `0xdebe` extension
/// block holding four one-byte-header elements (frame information, initial bandwidth, the offset from
/// capture to transmission, and a transport sequence number).
public struct CallVideoRTPHeader: Equatable, Sendable {
	public static let length = 28
	public static let h264PayloadType: UInt8 = 97
	public static let clockRate: UInt32 = 90_000
	/// Frame information of an upright IDR picture; the low two bits are its rotation.
	public static let frameInfoIDR: UInt8 = 0x08

	public var marker: Bool
	public var sequenceNumber: UInt16
	public var timestamp: UInt32
	public var ssrc: UInt32
	public var frameInfo: UInt8
	public var initialBandwidth: UInt16
	public var shortOffset: Int16
	public var transportSequence: UInt16

	public init(
		marker: Bool,
		sequenceNumber: UInt16,
		timestamp: UInt32,
		ssrc: UInt32,
		frameInfo: UInt8,
		initialBandwidth: UInt16 = 0,
		shortOffset: Int16 = 0,
		transportSequence: UInt16
	) {
		self.marker = marker
		self.sequenceNumber = sequenceNumber
		self.timestamp = timestamp
		self.ssrc = ssrc
		self.frameInfo = frameInfo
		self.initialBandwidth = initialBandwidth
		self.shortOffset = shortOffset
		self.transportSequence = transportSequence
	}

	public func encoded() -> Data {
		var bytes = [UInt8]()
		bytes.reserveCapacity(Self.length)
		bytes.append(0x80 | 0x10)
		bytes.append((marker ? 0x80 : 0) | Self.h264PayloadType)
		bytes += bigEndian(sequenceNumber)
		bytes += bigEndian(timestamp)
		bytes += bigEndian(ssrc)
		bytes += bigEndian(CallRTPHeader.extensionProfile)
		bytes += bigEndian(UInt16(3))
		bytes += [0x30, frameInfo, 0x51]
		bytes += bigEndian(initialBandwidth)
		bytes.append(0x61)
		bytes += bigEndian(UInt16(bitPattern: shortOffset))
		bytes.append(0x91)
		bytes += bigEndian(transportSequence)
		bytes.append(0)
		return Data(bytes)
	}

	private func bigEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
		withUnsafeBytes(of: value.bigEndian) { Array($0) }
	}
}

/// The elements of a packet's RTP extension block this client reads. The header is in the clear, so
/// these only mean something once the packet has authenticated.
struct CallRTPExtensionElements: Equatable {
	/// One-byte extension profile of RFC 8285, which WhatsApp also accepts for its audio piggyback.
	static let oneByteProfile: UInt16 = 0xbede
	static let frameInfoID: UInt8 = 3
	static let timeOffsetID: UInt8 = 6
	static let audioPiggybackID: UInt8 = 7

	var frameInfo: UInt8?
	var timeOffsetMs: Int16?
	/// Where a carried audio packet starts in the decrypted payload.
	var audioOffset: Int?

	init(packet: Data) {
		let bytes = [UInt8](packet.prefix(CallRTPHeader.fixedLength + 15 * 4 + 4 + 255 * 4))
		guard bytes.count >= CallRTPHeader.fixedLength, bytes[0] >> 6 == 2, bytes[0] & 0x10 != 0 else {
			return
		}

		let start = CallRTPHeader.fixedLength + Int(bytes[0] & 0x0f) * 4
		guard bytes.count >= start + 4 else {
			return
		}

		let profile = UInt16(bytes[start]) << 8 | UInt16(bytes[start + 1])
		guard profile == CallRTPHeader.extensionProfile || profile == Self.oneByteProfile else {
			return
		}

		let words = Int(bytes[start + 2]) << 8 | Int(bytes[start + 3])
		var cursor = start + 4
		let end = min(bytes.count, cursor + words * 4)
		var frameInfoFormat = Int.max
		while cursor < end {
			let header = bytes[cursor]
			cursor += 1
			let id = header >> 4
			if id == 0 {
				continue
			}
			if id == 15 {
				break
			}

			let length = Int(header & 0x0f) + 1
			guard cursor + length <= end else {
				break
			}

			switch id {
			case Self.frameInfoID where profile == CallRTPHeader.extensionProfile:
				// Three formats exist, and the shortest wins whatever the order.
				let format = length <= 2 ? 0 : length <= 5 ? 1 : 2
				if format < frameInfoFormat {
					frameInfoFormat = format
					frameInfo = bytes[cursor]
				}
			case Self.timeOffsetID where profile == CallRTPHeader.extensionProfile && length == 2:
				timeOffsetMs = Int16(bitPattern: UInt16(bytes[cursor]) << 8 | UInt16(bytes[cursor + 1]))
			case Self.audioPiggybackID where length == 2:
				audioOffset = Int(bytes[cursor]) << 8 | Int(bytes[cursor + 1])
			default:
				break
			}
			cursor += length
		}
	}

	/// Splits the audio packet a carrier holds off its decrypted payload. Padding, when the carrier
	/// has the P bit, ends the media part rather than the packet.
	static func splitCarriedAudio(packet: Data, payload: Data) -> (media: Data, audio: Data?) {
		let padded = (packet.first ?? 0) & 0x20 != 0
		let offset = CallRTPExtensionElements(packet: packet).audioOffset
		guard let offset, offset > 0, offset < payload.count else {
			return (padded ? removingPadding(payload) : payload, nil)
		}

		let media = Data(payload.prefix(offset))
		return (padded ? removingPadding(media) : media, Data(payload.dropFirst(offset)))
	}

	private static func removingPadding(_ data: Data) -> Data {
		guard let padding = data.last, Int(padding) <= data.count else {
			return data
		}

		return Data(data.dropLast(Int(padding)))
	}
}

/// One picture from the peer, as Annex-B H.264.
public struct CallVideoFrame: Equatable, Sendable {
	public let data: Data
	public let timestamp: UInt32
	public let isKeyframe: Bool
	/// Quarter turns the picture was rotated by on the sender's side, when its packets say.
	public let orientation: UInt8?

	public init(data: Data, timestamp: UInt32, isKeyframe: Bool, orientation: UInt8?) {
		self.data = data
		self.timestamp = timestamp
		self.isKeyframe = isKeyframe
		self.orientation = orientation
	}
}

/// SRTP receive step shared by the audio and video pipelines. It authenticates against the estimated
/// rollover counter before committing anything, so a forged packet cannot desync or fill the stream
/// table.
enum CallSRTPReceive {
	static func unprotect(
		_ packet: Data,
		keys: CallSRTPKeys,
		tagLength: Int,
		streams: inout [UInt32: CallAudioPipeline.ReceiveStream],
		maxStreams: Int
	) throws -> (header: CallRTPHeader, payload: Data) {
		guard packet.count >= CallRTPHeader.fixedLength + tagLength,
			  let header = CallRTPHeader.parse(packet),
			  let headerLength = CallRTPHeader.length(of: packet) else {
			throw CallAudioPipeline.ReceiveError.malformed
		}

		let split = packet.count - tagLength
		guard split > headerLength else {
			throw CallAudioPipeline.ReceiveError.malformed
		}

		let withoutTag = packet.prefix(split)
		let received = packet.suffix(tagLength)
		let stream = streams[header.ssrc] ?? CallAudioPipeline.ReceiveStream()
		guard let roc = stream.estimateROC(for: header.sequenceNumber) else {
			throw CallAudioPipeline.ReceiveError.malformed
		}
		guard CallMediaCrypto.verifyWarpTag(
			authKey: keys.authKey,
			packetWithoutTag: Data(withoutTag),
			roc: roc,
			receivedTag: Data(received)
		) else {
			throw CallAudioPipeline.ReceiveError.authenticationFailed
		}

		guard streams[header.ssrc] != nil || streams.count < maxStreams else {
			throw CallAudioPipeline.ReceiveError.replayed
		}

		var updated = stream
		guard updated.accept(sequence: header.sequenceNumber, roc: roc) else {
			throw CallAudioPipeline.ReceiveError.replayed
		}

		streams[header.ssrc] = updated
		let payload = try CallMediaCrypto.cryptPayload(
			Data(withoutTag.dropFirst(headerLength)),
			keys: keys,
			ssrc: header.ssrc,
			roc: roc,
			sequence: header.sequenceNumber
		)
		return (header, payload)
	}
}

/// Video sibling of `CallAudioPipeline`: the same per-participant keys and WARP tag, with its own
/// SSRC and sequencer, and H.264 packetization on top. One access unit becomes many packets on send
/// and is rebuilt from them on receive.
public struct CallVideoPipeline {
	/// How long a just-left video SSRC stays ignorable, in authenticated packets. A renumbering peer's
	/// old stream keeps arriving for a few milliseconds after its new one starts.
	static let retiredGracePackets = 64
	/// Packets in a row a retired SSRC must deliver past its grace to take reassembly back.
	static let retiredResumePackets = 3
	static let retiredMemory = 4
	static let maxReceiveStreams = 8

	public struct Received: Equatable, Sendable {
		public let header: CallRTPHeader
		public let frames: [CallVideoFrame]
		/// A complete audio RTP packet the sender carried inside this one.
		public let carriedAudio: Data?
		/// Packets of the stream being reassembled that are missing before this one.
		public let lost: UInt16
		public let payloadBytes: Int
		/// Whether this packet belongs to the stream being reassembled.
		public let isCurrentStream: Bool
	}

	public let ssrc: UInt32

	private var sendKeys: CallSRTPKeys
	private var receiveKeys: CallSRTPKeys
	private let tagLength: Int

	private var sequence: UInt16 = 0
	private var transportSequence: UInt16 = 0
	private var sendROC: UInt32 = 0
	private var lastSentSequence: UInt16?
	private var receiveStreams: [UInt32: CallAudioPipeline.ReceiveStream] = [:]

	private var depacketizer = CallH264Depacketizer()
	/// The peer stream being reassembled, once one has authenticated.
	public private(set) var inboundSSRC: UInt32?
	private var retiredSSRCs = [UInt32]()
	private var contenderSSRC: UInt32?
	private var packetsSinceStreamChange = 0
	private var retiredRun = 0
	private var expectedSequence: UInt16?
	private var pictureOrientation: (timestamp: UInt32, orientation: UInt8?)?

	public init(
		callKey: Data,
		selfParticipantID: String,
		peerParticipantID: String,
		ssrc: UInt32,
		tagLength: Int = CallMediaCrypto.warpTagLength
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
	}

	// MARK: Group keys

	/// Moves sending to a new group media key, carrying on the same stream.
	public mutating func rekeySend(callKey: Data, selfParticipantID: String) throws {
		sendKeys = try CallMediaCrypto.deriveRTPKeys(
			callKey: callKey,
			participantID: CallMediaCrypto.formatParticipantID(selfParticipantID)
		)
	}

	/// Moves receiving to a new group media key, keeping rollover state and what is half reassembled.
	public mutating func rekeyReceive(callKey: Data, peerParticipantID: String) throws {
		receiveKeys = try CallMediaCrypto.deriveRTPKeys(
			callKey: callKey,
			participantID: CallMediaCrypto.formatParticipantID(peerParticipantID)
		)
	}

	/// Forgets a half-built picture, so it cannot complete under a later roster.
	public mutating func resetReassembly() {
		depacketizer.reset()
		pictureOrientation = nil
		expectedSequence = nil
	}

	// MARK: Sending

	/// Protects one RTP payload of an access unit. `marker` closes the access unit.
	public mutating func protect(
		_ payload: Data,
		marker: Bool,
		timestamp: UInt32,
		frameInfo: UInt8,
		shortOffset: Int16
	) throws -> (packet: Data, sequence: UInt16) {
		let header = CallVideoRTPHeader(
			marker: marker,
			sequenceNumber: sequence,
			timestamp: timestamp,
			ssrc: ssrc,
			frameInfo: frameInfo,
			shortOffset: shortOffset,
			transportSequence: transportSequence
		)
		if let last = lastSentSequence, header.sequenceNumber < last {
			sendROC &+= 1
		}
		lastSentSequence = header.sequenceNumber
		sequence &+= 1
		transportSequence &+= 1

		var packet = header.encoded()
		try packet.append(CallMediaCrypto.cryptPayload(
			payload,
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
		return (packet, header.sequenceNumber)
	}

	// MARK: Receiving

	/// Authenticates, decrypts and reassembles one video packet.
	public mutating func unprotect(_ packet: Data) throws -> Received {
		let (header, decrypted) = try CallSRTPReceive.unprotect(
			packet,
			keys: receiveKeys,
			tagLength: tagLength,
			streams: &receiveStreams,
			maxStreams: Self.maxReceiveStreams
		)
		let (media, audio) = CallRTPExtensionElements.splitCarriedAudio(packet: packet, payload: decrypted)

		packetsSinceStreamChange += 1
		guard takeStreamOwnership(of: header.ssrc) else {
			// A straggler's picture is ignored, but the audio it carries is the peer's current audio.
			return Received(
				header: header,
				frames: [],
				carriedAudio: audio,
				lost: 0,
				payloadBytes: media.count,
				isCurrentStream: false
			)
		}

		let lost = missingPackets(before: header.sequenceNumber)
		let elements = CallRTPExtensionElements(packet: packet)
		let completed = depacketizer.push(
			sequence: header.sequenceNumber,
			timestamp: header.timestamp,
			offsetMs: elements.timeOffsetMs,
			payload: media,
			marker: header.marker
		)

		let frames = frames(from: completed, rotation: elements.frameInfo.map { $0 & 3 })
		return Received(
			header: header,
			frames: frames,
			carriedAudio: audio,
			lost: lost,
			payloadBytes: media.count,
			isCurrentStream: true
		)
	}

	/// Authenticates one of the peer's other streams (FEC, retransmissions, app data), which this
	/// client does not decode but which carry its audio piggybacked in a video call.
	public mutating func unprotectAuxiliary(_ packet: Data) throws -> Data? {
		let (_, decrypted) = try CallSRTPReceive.unprotect(
			packet,
			keys: receiveKeys,
			tagLength: tagLength,
			streams: &receiveStreams,
			maxStreams: Self.maxReceiveStreams
		)
		return CallRTPExtensionElements.splitCarriedAudio(packet: packet, payload: decrypted).audio
	}

	/// Pictures carry a rotation on each packet, and the access unit that closes may be the one before
	/// the packet just read, so the rotation is tracked per picture.
	private mutating func frames(
		from completed: [CallH264Depacketizer.AccessUnit],
		rotation: UInt8?
	) -> [CallVideoFrame] {
		let previous = pictureOrientation
		if let picture = depacketizer.lastPacketTimestamp {
			if let current = pictureOrientation, current.timestamp == picture {
				if let rotation {
					pictureOrientation = (picture, rotation)
				}
			} else if pictureOrientation.map({ Int32(bitPattern: picture &- $0.timestamp) > 0 }) ?? true {
				pictureOrientation = (picture, rotation)
			}
		}

		return completed.map { unit in
			let known = pictureOrientation?.timestamp == unit.timestamp ? pictureOrientation : previous
			return CallVideoFrame(
				data: unit.data,
				timestamp: unit.timestamp,
				isKeyframe: CallH264.hasIDR(unit.data),
				orientation: known?.timestamp == unit.timestamp ? known?.orientation : nil
			)
		}
	}

	/// Decides whether a packet from `incoming` may feed reassembly, moving it to that stream when so.
	///
	/// Reassembly keys on sequence numbers and timestamps, which mean nothing across streams, so a
	/// new stream discards what the last one left half built. An SSRC never seen before commits at
	/// once; one this pipeline has left must first outlast its grace and deliver a run of packets.
	private mutating func takeStreamOwnership(of incoming: UInt32) -> Bool {
		if inboundSSRC == incoming {
			retiredRun = 0
			return true
		}

		if retiredSSRCs.contains(incoming) {
			if contenderSSRC != incoming {
				contenderSSRC = incoming
				retiredRun = 0
			}
			retiredRun += 1
			if packetsSinceStreamChange <= Self.retiredGracePackets || retiredRun < Self.retiredResumePackets {
				return false
			}
		}

		if let left = inboundSSRC {
			depacketizer.reset()
			pictureOrientation = nil
			retiredSSRCs.removeAll { $0 == left }
			if retiredSSRCs.count == Self.retiredMemory {
				retiredSSRCs.removeFirst()
			}
			retiredSSRCs.append(left)
		}
		retiredSSRCs.removeAll { $0 == incoming }
		inboundSSRC = incoming
		packetsSinceStreamChange = 0
		retiredRun = 0
		contenderSSRC = nil
		expectedSequence = nil
		return true
	}

	private mutating func missingPackets(before sequence: UInt16) -> UInt16 {
		defer {
			if let expected = expectedSequence, sequence &- expected >= 0x8000 {
				// A late packet does not move the expectation back.
			} else {
				expectedSequence = sequence &+ 1
			}
		}

		guard let expected = expectedSequence else {
			return 0
		}

		let ahead = sequence &- expected
		return ahead >= 0x8000 ? 0 : ahead
	}
}
