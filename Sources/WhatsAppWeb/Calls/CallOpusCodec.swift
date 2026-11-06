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
