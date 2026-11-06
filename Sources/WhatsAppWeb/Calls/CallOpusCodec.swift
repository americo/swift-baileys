import AVFoundation
import AudioToolbox
import Foundation

public enum CallOpusError: Error, Equatable, Sendable {
	case unsupportedFormat
	case converterUnavailable
	case wrongFrameSize(Int)
	case encodeFailed(String)
	case decodeFailed(String)
}

/// Audio format of a call leg: 16 kHz mono, 60 ms Opus frames (960 samples).
public enum CallAudioFormat {
	public static let sampleRate: Double = 16_000
	public static let samplesPerFrame = 960
	public static let maxPacketBytes = 1_500

	static var pcm: AVAudioFormat? {
		AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)
	}

	static var opus: AVAudioFormat? {
		var description = AudioStreamBasicDescription(
			mSampleRate: sampleRate,
			mFormatID: kAudioFormatOpus,
			mFormatFlags: 0,
			mBytesPerPacket: 0,
			mFramesPerPacket: UInt32(samplesPerFrame),
			mBytesPerFrame: 0,
			mChannelsPerFrame: 1,
			mBitsPerChannel: 0,
			mReserved: 0
		)
		return AVAudioFormat(streamDescription: &description)
	}
}

/// Opus encoder backed by the system AudioToolbox codec. One call encodes one 60 ms frame.
public final class CallOpusEncoder {
	private let converter: AVAudioConverter
	private let pcmFormat: AVAudioFormat
	private let opusFormat: AVAudioFormat

	public init(bitRate: Int = 24_000) throws {
		guard let pcm = CallAudioFormat.pcm, let opus = CallAudioFormat.opus else {
			throw CallOpusError.unsupportedFormat
		}
		guard let converter = AVAudioConverter(from: pcm, to: opus) else {
			throw CallOpusError.converterUnavailable
		}

		converter.bitRate = bitRate
		self.converter = converter
		self.pcmFormat = pcm
		self.opusFormat = opus
	}

	public func encode(_ samples: [Int16]) throws -> Data {
		guard samples.count == CallAudioFormat.samplesPerFrame else {
			throw CallOpusError.wrongFrameSize(samples.count)
		}
		guard let input = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
			throw CallOpusError.encodeFailed("no input buffer")
		}

		input.frameLength = AVAudioFrameCount(samples.count)
		samples.withUnsafeBufferPointer { source in
			input.int16ChannelData?[0].update(from: source.baseAddress!, count: samples.count)
		}

		let output = AVAudioCompressedBuffer(
			format: opusFormat,
			packetCapacity: 1,
			maximumPacketSize: CallAudioFormat.maxPacketBytes
		)
		var supplied = false
		var error: NSError?
		let status = converter.convert(to: output, error: &error) { _, inputStatus in
			if supplied {
				inputStatus.pointee = .noDataNow
				return nil
			}

			supplied = true
			inputStatus.pointee = .haveData
			return input
		}

		guard status != .error, error == nil else {
			throw CallOpusError.encodeFailed(error?.localizedDescription ?? "converter error")
		}
		guard output.packetCount > 0, output.byteLength > 0 else {
			throw CallOpusError.encodeFailed("no packet produced")
		}

		return Data(bytes: output.data, count: Int(output.byteLength))
	}
}

/// Reads the frames out of an Opus packet (RFC 6716 §3.2).
///
/// A WhatsApp client in a video call sends two 60 ms frames per packet, and the system decoder
/// produces nothing for a packet holding more than one frame.
enum CallOpusPacket {
	/// Each frame of `packet` as a packet of its own. `nil` when the packet is malformed.
	static func frames(in packet: Data) -> [Data]? {
		let bytes = [UInt8](packet)
		guard let toc = bytes.first else {
			return nil
		}

		let code = toc & 0x03
		if code == 0 {
			return [packet]
		}

		let singleFrameTOC = toc & 0xfc
		var ranges = [Range<Int>]()
		switch code {
		case 1:
			let body = bytes.count - 1
			guard body % 2 == 0 else {
				return nil
			}
			ranges = [1..<(1 + body / 2), (1 + body / 2)..<bytes.count]
		case 2:
			guard let (first, cursor) = frameLength(bytes, at: 1), cursor + first <= bytes.count else {
				return nil
			}
			ranges = [cursor..<(cursor + first), (cursor + first)..<bytes.count]
		default:
			guard let parsed = codeThreeRanges(bytes) else {
				return nil
			}
			ranges = parsed
		}

		// A frame with no bytes says nothing was sent for that time, and has nothing to decode.
		return ranges.filter { !$0.isEmpty }.map { Data([singleFrameTOC] + bytes[$0]) }
	}

	private static func codeThreeRanges(_ bytes: [UInt8]) -> [Range<Int>]? {
		guard bytes.count >= 2 else {
			return nil
		}

		let header = bytes[1]
		let isVariable = header & 0x80 != 0
		let hasPadding = header & 0x40 != 0
		let count = Int(header & 0x3f)
		guard count > 0 else {
			return nil
		}

		var cursor = 2
		var padding = 0
		if hasPadding {
			while true {
				guard cursor < bytes.count else {
					return nil
				}

				let value = Int(bytes[cursor])
				cursor += 1
				padding += value == 255 ? 254 : value
				if value != 255 {
					break
				}
			}
		}

		let end = bytes.count - padding
		var lengths = [Int]()
		if isVariable {
			for _ in 0..<(count - 1) {
				guard let (length, next) = frameLength(bytes, at: cursor), next <= end else {
					return nil
				}
				lengths.append(length)
				cursor = next
			}
		}
		guard end >= cursor else {
			return nil
		}

		if isVariable {
			let used = lengths.reduce(0, +)
			guard used <= end - cursor else {
				return nil
			}
			lengths.append(end - cursor - used)
		} else {
			guard (end - cursor) % count == 0 else {
				return nil
			}
			lengths = Array(repeating: (end - cursor) / count, count: count)
		}

		var ranges = [Range<Int>]()
		for length in lengths {
			ranges.append(cursor..<(cursor + length))
			cursor += length
		}
		return ranges
	}

	/// A frame length: one byte up to 251, and two above that.
	private static func frameLength(_ bytes: [UInt8], at index: Int) -> (length: Int, next: Int)? {
		guard index < bytes.count else {
			return nil
		}

		let first = Int(bytes[index])
		if first < 252 {
			return (first, index + 1)
		}
		guard index + 1 < bytes.count else {
			return nil
		}

		return (Int(bytes[index + 1]) * 4 + first, index + 2)
	}
}

/// Opus decoder backed by the system AudioToolbox codec.
public final class CallOpusDecoder {
	private let converter: AVAudioConverter
	private let pcmFormat: AVAudioFormat
	private let opusFormat: AVAudioFormat

	public init() throws {
		guard let pcm = CallAudioFormat.pcm, let opus = CallAudioFormat.opus else {
			throw CallOpusError.unsupportedFormat
		}
		guard let converter = AVAudioConverter(from: opus, to: pcm) else {
			throw CallOpusError.converterUnavailable
		}

		self.converter = converter
		self.pcmFormat = pcm
		self.opusFormat = opus
	}

	/// Decodes one Opus packet. The result is as long as the packet's own duration.
	public func decode(_ packet: Data) throws -> [Int16] {
		guard !packet.isEmpty, packet.count <= CallAudioFormat.maxPacketBytes else {
			throw CallOpusError.decodeFailed("invalid packet size")
		}
		guard let frames = CallOpusPacket.frames(in: packet) else {
			throw CallOpusError.decodeFailed("malformed packet")
		}

		return try frames.flatMap(decodeFrame)
	}

	private func decodeFrame(_ packet: Data) throws -> [Int16] {
		let input = AVAudioCompressedBuffer(
			format: opusFormat,
			packetCapacity: 1,
			maximumPacketSize: CallAudioFormat.maxPacketBytes
		)
		packet.copyBytes(to: input.data.assumingMemoryBound(to: UInt8.self), count: packet.count)
		input.byteLength = UInt32(packet.count)
		input.packetCount = 1
		input.packetDescriptions?[0] = AudioStreamPacketDescription(
			mStartOffset: 0,
			mVariableFramesInPacket: 0,
			mDataByteSize: UInt32(packet.count)
		)

		// 120 ms is the longest Opus packet.
		let capacity = AVAudioFrameCount(CallAudioFormat.samplesPerFrame * 2)
		guard let output = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: capacity) else {
			throw CallOpusError.decodeFailed("no output buffer")
		}

		var supplied = false
		var error: NSError?
		let status = converter.convert(to: output, error: &error) { _, inputStatus in
			if supplied {
				inputStatus.pointee = .noDataNow
				return nil
			}

			supplied = true
			inputStatus.pointee = .haveData
			return input
		}

		guard status != .error, error == nil else {
			throw CallOpusError.decodeFailed(error?.localizedDescription ?? "converter error")
		}
		guard let channel = output.int16ChannelData?[0] else {
			throw CallOpusError.decodeFailed("no samples")
		}

		return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
	}
}
