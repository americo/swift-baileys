import CryptoKit
import Foundation

/// RTCP as WhatsApp's 1:1 calls use it, which the video path depends on: a receiver asks for
/// keyframes with PLI, a sender answers NACKs, and each side reports what reached it. A native sender
/// lowers its video when it has no statement of what reached the other end.
public enum CallRTCP {
	static let typeSenderReport: UInt8 = 200
	static let typeReceiverReport: UInt8 = 201
	static let typeSourceDescription: UInt8 = 202
	static let typeTransportFeedback: UInt8 = 205
	static let typePayloadFeedback: UInt8 = 206
	/// Set beside the count or FMT on the native video profile. Parsers mask it off.
	static let profileExtensionBit: UInt8 = 0x10
	static let feedbackFormatNACK: UInt8 = 1
	static let feedbackFormatPLI: UInt8 = 1
	static let feedbackFormatFIR: UInt8 = 4
	static let cnameLength = 18

	private static let ntpUnixOffset: UInt64 = 2_208_988_800
	/// Native report blocks follow the RFC 3550 block with 24 bytes of transport statistics.
	private static let reportExtensionLength = 24

	public struct ReportBlock: Equatable, Sendable {
		public let ssrc: UInt32
		public let fractionLost: UInt8
	}

	public struct Feedback: Equatable, Sendable {
		public let packetType: UInt8
		public let format: UInt8
		public let senderSSRC: UInt32
		public let mediaSSRC: UInt32
		public let controlInformation: [UInt8]
	}

	public struct SenderTiming: Equatable, Sendable {
		public let ssrc: UInt32
		/// Middle 32 bits of the NTP timestamp, which a report block echoes back.
		public let compactNTP: UInt32
	}

	public struct Summary: Equatable, Sendable {
		public var reportBlocks: [ReportBlock] = []
		public var feedback: [Feedback] = []
		public var senderTimings: [SenderTiming] = []
	}

	public struct ReceptionReport: Equatable, Sendable {
		public var ssrc: UInt32
		public var fractionLost: UInt8
		public var cumulativeLost: Int32
		public var extendedHighestSequence: UInt32
		public var jitter: UInt32
		public var lastSenderReport: UInt32
		public var delaySinceLastSenderReport: UInt32
		public var bytesReceived: UInt32
		public var receiveRateBps: UInt32
	}

	// MARK: Parsing

	/// Parses a decrypted compound packet. `nil` when it is malformed.
	public static func parse(_ data: Data) -> Summary? {
		let bytes = [UInt8](data)
		var summary = Summary()
		var offset = 0
		while offset < bytes.count {
			guard offset + 4 <= bytes.count, bytes[offset] >> 6 == 2, (192...223).contains(bytes[offset + 1]) else {
				return nil
			}

			let length = (Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3]) + 1) * 4
			guard length >= 8, offset + length <= bytes.count else {
				return nil
			}

			var packet = Array(bytes[offset..<(offset + length)])
			if packet[0] & 0x20 != 0 {
				guard offset + length == bytes.count, let padding = packet.last.map(Int.init),
					  padding > 0, padding % 4 == 0, padding <= packet.count - 8 else {
					return nil
				}
				packet.removeLast(padding)
			}

			guard read(packet, into: &summary) else {
				return nil
			}

			offset += length
		}

		return summary
	}

	private static func read(_ packet: [UInt8], into summary: inout Summary) -> Bool {
		let type = packet[1]
		let rawCount = Int(packet[0] & 0x1f)
		let sender = be32(packet, 4)

		switch type {
		case typeSenderReport, typeReceiverReport:
			let start = type == typeSenderReport ? 28 : 8
			guard packet.count >= start else {
				return false
			}
			if type == typeSenderReport {
				summary.senderTimings.append(SenderTiming(ssrc: sender, compactNTP: be32(packet, 10)))
			}
			guard let blocks = reportBlocks(packet, start: start, rawCount: rawCount) else {
				return false
			}
			summary.reportBlocks += blocks
		case typeTransportFeedback, typePayloadFeedback:
			guard packet.count >= 12 else {
				return true
			}
			summary.feedback.append(Feedback(
				packetType: type,
				format: UInt8(rawCount & 0x0f),
				senderSSRC: sender,
				mediaSSRC: be32(packet, 8),
				controlInformation: Array(packet[12...])
			))
		default:
			break
		}

		return true
	}

	/// Report blocks are 24 bytes on the RFC profile and longer on the native one, where the count
	/// also carries the profile bit.
	private static func reportBlocks(_ packet: [UInt8], start: Int, rawCount: Int) -> [ReportBlock]? {
		let available = packet.count - start
		var count = rawCount
		if available < count * 24, rawCount & Int(profileExtensionBit) != 0 {
			count = rawCount & 0x0f
		}
		if count == 0 {
			return []
		}
		guard available >= count * 24 else {
			return nil
		}

		let stride = available % count == 0 ? available / count : 24
		guard stride >= 24 else {
			return nil
		}

		return (0..<count).map { index in
			let at = start + index * stride
			return ReportBlock(ssrc: be32(packet, at), fractionLost: packet[at + 4])
		}
	}

	/// Whether the peer's feedback asks for a keyframe of `ssrc`, by PLI or FIR.
	static func requestsKeyframe(_ feedback: [Feedback], ssrc: UInt32) -> Bool {
		feedback.contains { item in
			guard item.packetType == typePayloadFeedback else {
				return false
			}

			switch item.format {
			case feedbackFormatPLI:
				return item.mediaSSRC == ssrc
			case feedbackFormatFIR:
				if item.mediaSSRC == ssrc {
					return true
				}
				return stride(from: 0, to: item.controlInformation.count - 7, by: 8).contains {
					be32(item.controlInformation, $0) == ssrc
				}
			default:
				return false
			}
		}
	}

	/// Sequence numbers of `ssrc` the peer's generic NACKs ask for (RFC 4585 §6.2.1).
	static func nackedSequences(_ feedback: [Feedback], ssrc: UInt32) -> [UInt16] {
		var sequences = [UInt16]()
		for item in feedback where item.packetType == typeTransportFeedback
			&& item.format == feedbackFormatNACK && item.mediaSSRC == ssrc {
			let fci = item.controlInformation
			for row in stride(from: 0, to: fci.count - 3, by: 4) {
				let first = UInt16(fci[row]) << 8 | UInt16(fci[row + 1])
				let mask = UInt16(fci[row + 2]) << 8 | UInt16(fci[row + 3])
				sequences.append(first)
				for bit in 0..<16 where mask & (1 << UInt16(bit)) != 0 {
					sequences.append(first &+ UInt16(bit) &+ 1)
				}
			}
		}

		return sequences
	}

	// MARK: Building

	/// A Picture Loss Indication on the native video profile, whose receivers recognise it by that bit.
	public static func pictureLossIndication(senderSSRC: UInt32, mediaSSRC: UInt32) -> Data {
		var bytes: [UInt8] = [0x80 | profileExtensionBit | feedbackFormatPLI, typePayloadFeedback, 0, 2]
		bytes += bigEndian(senderSSRC)
		bytes += bigEndian(mediaSSRC)
		return Data(bytes)
	}

	/// The periodic compound report: a Sender Report, with the block for the stream being received
	/// when there is one, and an SDES naming the sender, on the native video profile.
	public static func senderReport(
		ssrc: UInt32,
		rtpTimestamp: UInt32,
		packetsSent: UInt32,
		octetsSent: UInt32,
		wallclockMs: UInt64,
		cname: [UInt8],
		report: ReceptionReport?
	) -> Data {
		var bytes: [UInt8] = [0x80 | profileExtensionBit | (report == nil ? 0 : 1), typeSenderReport, 0, 0]
		bytes += bigEndian(ssrc)
		bytes += bigEndian(UInt32(truncatingIfNeeded: wallclockMs / 1000 + ntpUnixOffset))
		bytes += bigEndian(UInt32(Double(wallclockMs % 1000) / 1000 * 4_294_967_296))
		bytes += bigEndian(rtpTimestamp)
		bytes += bigEndian(packetsSent)
		bytes += bigEndian(octetsSent)
		if let report {
			bytes += bigEndian(report.ssrc)
			bytes.append(report.fractionLost)
			bytes += bigEndian(UInt32(bitPattern: report.cumulativeLost)).dropFirst()
			bytes += bigEndian(report.extendedHighestSequence)
			bytes += bigEndian(report.jitter)
			bytes += bigEndian(report.lastSenderReport)
			bytes += bigEndian(report.delaySinceLastSenderReport)
			// The first word is what reached us and the sixth the rate it arrived at. The rest stay
			// zero, which is the native "not available".
			var statistics = [UInt8](repeating: 0, count: reportExtensionLength)
			statistics.replaceSubrange(0..<4, with: bigEndian(report.bytesReceived))
			statistics.replaceSubrange(20..<24, with: bigEndian(report.receiveRateBps))
			bytes += statistics
		}
		let words = bytes.count / 4 - 1
		bytes[2] = UInt8(words >> 8)
		bytes[3] = UInt8(words & 0xff)

		bytes += sourceDescription(ssrc: ssrc, cname: cname)
		return Data(bytes)
	}

	private static func sourceDescription(ssrc: UInt32, cname: [UInt8]) -> [UInt8] {
		var bytes = [UInt8](repeating: 0, count: 32)
		bytes[0] = 0x80 | profileExtensionBit | 1
		bytes[1] = typeSourceDescription
		bytes[3] = 7
		bytes.replaceSubrange(4..<8, with: bigEndian(ssrc))
		bytes[8] = 1
		bytes[9] = UInt8(cnameLength)
		bytes.replaceSubrange(10..<(10 + cnameLength), with: cname.prefix(cnameLength))
		return bytes
	}

	/// WhatsApp's CNAME: 18 characters shaped like `abcde@pj012345.org`.
	static func cname(ssrc: UInt32, callKey: Data) -> [UInt8] {
		let digest = SHA256.hash(data: withUnsafeBytes(of: ssrc.bigEndian) { Data($0) } + callKey.prefix(2))
		let hex = Array(digest.map { String(format: "%02x", $0) }.joined().utf8.prefix(11))
		return Array(hex[0..<5]) + Array("@pj".utf8) + Array(hex[5..<11]) + Array(".org".utf8)
	}

	// MARK: Bytes

	private static func be32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
		guard at + 4 <= bytes.count else {
			return 0
		}

		return (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[at + $1]) }
	}

	private static func bigEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
		withUnsafeBytes(of: value.bigEndian) { Array($0) }
	}
}

/// What has arrived on a received stream, for the report block back to its sender (RFC 3550 A.3).
struct CallRTPReceptionStats {
	private var ssrc: UInt32?
	private var baseSequence: UInt16 = 0
	private var maxSequence: UInt16 = 0
	private var cycles: UInt32 = 0
	private var received: UInt32 = 0
	private var expectedPrior: UInt32 = 0
	private var receivedPrior: UInt32 = 0
	private var payloadBytes: UInt64 = 0
	private var payloadBytesPrior: UInt64 = 0
	private var reportedAtMs: UInt64?
	private var lastTransit: Int64?
	private var jitter: Double = 0
	private var lastSenderReport: UInt32 = 0
	private var lastSenderReportAtMs: UInt64?

	mutating func observe(ssrc incoming: UInt32, sequence: UInt16, timestamp: UInt32, arrivalMs: UInt64, payload: Int) {
		if ssrc != incoming {
			self = CallRTPReceptionStats()
			ssrc = incoming
			baseSequence = sequence
			maxSequence = sequence
			received = 1
		} else {
			let delta = sequence &- maxSequence
			if delta != 0, delta < 0x8000 {
				if sequence < maxSequence {
					cycles &+= 1 << 16
				}
				maxSequence = sequence
			}
			received &+= 1
		}
		payloadBytes += UInt64(payload)

		let arrivalTicks = Int64(arrivalMs) * Int64(CallVideoRTPHeader.clockRate) / 1000
		let transit = arrivalTicks - Int64(timestamp)
		if let lastTransit {
			jitter += (Double(abs(transit - lastTransit)) - jitter) / 16
		}
		lastTransit = transit
	}

	mutating func observeSenderReport(ssrc reported: UInt32, compactNTP: UInt32, arrivalMs: UInt64) {
		guard ssrc == reported else {
			return
		}

		lastSenderReport = compactNTP
		lastSenderReportAtMs = arrivalMs
	}

	mutating func report(nowMs: UInt64) -> CallRTCP.ReceptionReport? {
		guard let ssrc else {
			return nil
		}

		let expected = cycles &+ UInt32(maxSequence) &- UInt32(baseSequence) &+ 1
		let expectedInterval = expected &- expectedPrior
		let receivedInterval = received &- receivedPrior
		let lostInterval = Int64(expectedInterval) - Int64(receivedInterval)
		let fraction = expectedInterval == 0 || lostInterval <= 0
			? 0
			: UInt8(min((lostInterval * 256) / Int64(expectedInterval), 255))
		expectedPrior = expected
		receivedPrior = received

		var rate: UInt32 = 0
		if let reportedAtMs, nowMs > reportedAtMs {
			let bits = (payloadBytes - payloadBytesPrior) * 8
			rate = UInt32(min(bits * 1000 / (nowMs - reportedAtMs), UInt64(UInt32.max)))
		}
		payloadBytesPrior = payloadBytes
		reportedAtMs = nowMs

		return CallRTCP.ReceptionReport(
			ssrc: ssrc,
			fractionLost: fraction,
			cumulativeLost: Int32(clamping: Int64(expected) - Int64(received)),
			extendedHighestSequence: cycles &+ UInt32(maxSequence),
			jitter: UInt32(jitter),
			lastSenderReport: lastSenderReport,
			delaySinceLastSenderReport: lastSenderReportAtMs.map {
				UInt32(min(nowMs.saturating(minus: $0) * 65_536 / 1000, UInt64(UInt32.max)))
			} ?? 0,
			bytesReceived: UInt32(truncatingIfNeeded: payloadBytes),
			receiveRateBps: rate
		)
	}
}

private extension UInt64 {
	func saturating(minus other: UInt64) -> UInt64 {
		self > other ? self - other : 0
	}
}

/// Rejects replayed SRTCP by its authenticated index, per sender.
struct CallSRTCPReplayWindow {
	private var highest: [UInt32: UInt32] = [:]
	private var seen: [UInt32: UInt64] = [:]

	mutating func accept(sender: UInt32, index: UInt32) -> Bool {
		guard let top = highest[sender] else {
			guard highest.count < 8 else {
				return false
			}

			highest[sender] = index
			seen[sender] = 1
			return true
		}

		if index > top {
			let shift = index - top
			seen[sender] = shift >= 64 ? 1 : (seen[sender, default: 0] << UInt64(shift)) | 1
			highest[sender] = index
			return true
		}

		let age = top - index
		guard age < 64, seen[sender, default: 0] & (1 << UInt64(age)) == 0 else {
			return false
		}

		seen[sender, default: 0] |= 1 << UInt64(age)
		return true
	}
}

extension CallMediaCrypto {
	/// Inverse of `protectRTCP`: verifies the tag, then decrypts the body. `nil` on a bad tag or a
	/// packet too short to hold one.
	public static func unprotectRTCP(_ packet: Data, keys: CallSRTPKeys, senderSSRC: UInt32) -> (rtcp: Data, index: UInt32)? {
		let headerLength = 8
		guard packet.count >= headerLength + 4 + srtcpAuthTagLength else {
			return nil
		}

		let bytes = [UInt8](packet)
		let tagStart = bytes.count - srtcpAuthTagLength
		let mac = HMAC<Insecure.SHA1>.authenticationCode(
			for: Data(bytes[..<tagStart]),
			using: SymmetricKey(data: keys.authKey)
		)
		var difference: UInt8 = 0
		for (expected, received) in zip(Data(mac).prefix(srtcpAuthTagLength), bytes[tagStart...]) {
			difference |= expected ^ received
		}
		guard difference == 0 else {
			return nil
		}

		let indexStart = tagStart - 4
		let index = (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[indexStart + $1]) } & 0x7fff_ffff
		let iv = rtpIV(salt: keys.salt, ssrc: senderSSRC, roc: index >> 16, sequence: UInt16(index & 0xffff))
		guard let body = try? aesCTR(key: keys.cipherKey, iv: iv, input: Data(bytes[headerLength..<indexStart])) else {
			return nil
		}

		return (Data(bytes[..<headerLength]) + body, index)
	}
}
