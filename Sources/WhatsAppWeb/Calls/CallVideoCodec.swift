@preconcurrency import CoreMedia
@preconcurrency import CoreVideo
import Foundation
@preconcurrency import VideoToolbox

public enum CallVideoCodecError: Error, Equatable, Sendable {
	case sessionCreationFailed(OSStatus)
	case invalidDimensions
}

/// One encoded picture, as Annex-B with its parameter sets in front of every IDR.
public struct CallEncodedVideoFrame: Sendable {
	public let accessUnit: Data
	/// Capture time on the 90 kHz RTP clock.
	public let timestamp: UInt32
	public let isKeyframe: Bool
	public let capturedAt: ContinuousClock.Instant
}

/// H.264 encoder for a call, on VideoToolbox: Constrained Baseline with no reordering, which is what
/// every WhatsApp client can decode and what a live call needs.
public final class CallVideoEncoder: @unchecked Sendable {
	public static let frameRate = 20
	/// Seconds between keyframes. Any picture lost in between stays broken until the next one or until
	/// a request from the peer answers it, and not every peer asks.
	public static let keyframeIntervalSeconds = 2

	public let width: Int
	public let height: Int

	private let lock = NSLock()
	private var session: VTCompressionSession?
	private var forceKeyframe = true
	private var firstPresentation: CMTime?
	private var lastEncoded: CMTime?
	private let output: @Sendable (CallEncodedVideoFrame) -> Void

	public init(
		width: Int,
		height: Int,
		bitrate: Int,
		output: @escaping @Sendable (CallEncodedVideoFrame) -> Void
	) throws {
		guard width > 0, height > 0 else {
			throw CallVideoCodecError.invalidDimensions
		}

		self.width = width
		self.height = height
		self.output = output

		var created: VTCompressionSession?
		let status = VTCompressionSessionCreate(
			allocator: kCFAllocatorDefault,
			width: Int32(width),
			height: Int32(height),
			codecType: kCMVideoCodecType_H264,
			encoderSpecification: nil,
			imageBufferAttributes: nil,
			compressedDataAllocator: nil,
			outputCallback: nil,
			refcon: nil,
			compressionSessionOut: &created
		)
		guard status == noErr, let created else {
			throw CallVideoCodecError.sessionCreationFailed(status)
		}

		let properties: [CFString: Any] = [
			kVTCompressionPropertyKey_RealTime: true,
			kVTCompressionPropertyKey_AllowFrameReordering: false,
			kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_ConstrainedBaseline_AutoLevel,
			kVTCompressionPropertyKey_H264EntropyMode: kVTH264EntropyMode_CAVLC,
			kVTCompressionPropertyKey_ExpectedFrameRate: Self.frameRate,
			kVTCompressionPropertyKey_MaxKeyFrameInterval: Self.frameRate * Self.keyframeIntervalSeconds,
			kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: Self.keyframeIntervalSeconds
		]
		for (key, value) in properties {
			VTSessionSetProperty(created, key: key, value: value as CFTypeRef)
		}
		applyBitrate(bitrate, to: created)
		VTCompressionSessionPrepareToEncodeFrames(created)
		session = created
	}

	deinit {
		invalidate()
	}

	/// Encodes one captured picture. Pictures faster than the call's frame rate are skipped.
	public func encode(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
		lock.lock()
		guard let session else {
			lock.unlock()
			return
		}

		if let lastEncoded, !forceKeyframe {
			// Slack so a camera running at exactly the frame rate is never thinned out by jitter.
			let minimum = 0.8 / Double(Self.frameRate)
			if CMTimeGetSeconds(CMTimeSubtract(presentationTime, lastEncoded)) < minimum {
				lock.unlock()
				return
			}
		}
		lastEncoded = presentationTime

		let first = firstPresentation ?? presentationTime
		firstPresentation = first
		let wantsKeyframe = forceKeyframe
		forceKeyframe = false
		lock.unlock()

		let elapsed = max(0, CMTimeGetSeconds(CMTimeSubtract(presentationTime, first)))
		let timestamp = UInt32(truncatingIfNeeded: UInt64(elapsed * Double(CallVideoRTPHeader.clockRate)))
		let capturedAt = ContinuousClock.now
		let properties: CFDictionary? = wantsKeyframe
			? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
			: nil
		let output = output

		let status = VTCompressionSessionEncodeFrame(
			session,
			imageBuffer: pixelBuffer,
			presentationTimeStamp: presentationTime,
			duration: .invalid,
			frameProperties: properties,
			infoFlagsOut: nil
		) { status, _, sampleBuffer in
			guard status == noErr, let sampleBuffer, let (unit, isKeyframe) = Self.annexB(from: sampleBuffer) else {
				return
			}

			output(CallEncodedVideoFrame(
				accessUnit: unit,
				timestamp: timestamp,
				isKeyframe: isKeyframe,
				capturedAt: capturedAt
			))
		}
		if status != noErr {
			requestKeyframe()
		}
	}

	/// Makes the next picture an IDR.
	public func requestKeyframe() {
		lock.lock()
		forceKeyframe = true
		lock.unlock()
	}

	public func setBitrate(_ bitrate: Int) {
		lock.lock()
		defer { lock.unlock() }
		if let session {
			applyBitrate(bitrate, to: session)
		}
	}

	public func invalidate() {
		lock.lock()
		let current = session
		session = nil
		lock.unlock()

		if let current {
			VTCompressionSessionInvalidate(current)
		}
	}

	private func applyBitrate(_ bitrate: Int, to session: VTCompressionSession) {
		VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFTypeRef)
		// A hard ceiling over one second, in bytes, so a keyframe cannot flood the path.
		let limits = [Double(bitrate) * 1.5 / 8, 1] as CFArray
		VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limits)
	}

	/// VideoToolbox hands out length-prefixed NALs and keeps the parameter sets in the format
	/// description. The wire wants start codes, with the parameter sets ahead of each IDR.
	static func annexB(from sampleBuffer: CMSampleBuffer) -> (Data, isKeyframe: Bool)? {
		guard CMSampleBufferDataIsReady(sampleBuffer),
			  let block = CMSampleBufferGetDataBuffer(sampleBuffer),
			  let format = CMSampleBufferGetFormatDescription(sampleBuffer) else {
			return nil
		}

		let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
		let isKeyframe = (attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) != true

		var unit = Data()
		if isKeyframe {
			var count = 0
			var headerLength: Int32 = 0
			CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
				format,
				parameterSetIndex: 0,
				parameterSetPointerOut: nil,
				parameterSetSizeOut: nil,
				parameterSetCountOut: &count,
				nalUnitHeaderLengthOut: &headerLength
			)
			for index in 0..<count {
				var pointer: UnsafePointer<UInt8>?
				var size = 0
				guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
					format,
					parameterSetIndex: index,
					parameterSetPointerOut: &pointer,
					parameterSetSizeOut: &size,
					parameterSetCountOut: nil,
					nalUnitHeaderLengthOut: nil
				) == noErr, let pointer else {
					return nil
				}

				unit.append(contentsOf: CallH264.startCode)
				unit.append(pointer, count: size)
			}
		}

		var total = 0
		var bytes: UnsafeMutablePointer<CChar>?
		guard CMBlockBufferGetDataPointer(
			block,
			atOffset: 0,
			lengthAtOffsetOut: nil,
			totalLengthOut: &total,
			dataPointerOut: &bytes
		) == noErr, let bytes else {
			return nil
		}

		let raw = UnsafeRawPointer(bytes)
		var cursor = 0
		while cursor + 4 <= total {
			let length = Int(UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: cursor, as: UInt32.self)))
			cursor += 4
			guard length > 0, cursor + length <= total else {
				return nil
			}

			unit.append(contentsOf: CallH264.startCode)
			unit.append(raw.advanced(by: cursor).assumingMemoryBound(to: UInt8.self), count: length)
			cursor += length
		}

		return unit.isEmpty ? nil : (unit, isKeyframe)
	}
}

/// H.264 decoder for a call, on VideoToolbox. Takes the Annex-B pictures `CallSession` produces and
/// hands out pixel buffers, and says when only a keyframe can get it going again.
public final class CallVideoDecoder: @unchecked Sendable {
	public enum Outcome: Equatable, Sendable {
		case decoded
		/// The picture could not be used. Nothing will decode until the peer sends a keyframe.
		case needsKeyframe
	}

	private var session: VTDecompressionSession?
	private var format: CMVideoFormatDescription?
	private var sps: Data?
	private var pps: Data?
	private var awaitingKeyframe = true
	private let output: @Sendable (CVPixelBuffer) -> Void

	/// `output` runs on the thread calling `decode`.
	public init(output: @escaping @Sendable (CVPixelBuffer) -> Void) {
		self.output = output
	}

	deinit {
		invalidate()
	}

	/// Decodes one access unit. Call it from one thread at a time.
	public func decode(_ accessUnit: Data) -> Outcome {
		var slices = [Data]()
		var newSPS: Data?
		var newPPS: Data?
		var hasIDR = false
		for nal in CallH264.splitAnnexB(accessUnit) {
			switch CallH264.nalType(nal) {
			case CallH264.typeSPS:
				newSPS = nal
			case CallH264.typePPS:
				newPPS = nal
			case CallH264.typeIDR:
				hasIDR = true
				slices.append(nal)
			case 1...4:
				slices.append(nal)
			default:
				break
			}
		}

		if let newSPS, let newPPS, newSPS != sps || newPPS != pps {
			guard configure(sps: newSPS, pps: newPPS) else {
				return .needsKeyframe
			}
		}

		guard let session, let format, !slices.isEmpty else {
			return session == nil ? .needsKeyframe : .decoded
		}

		if awaitingKeyframe, !hasIDR {
			return .needsKeyframe
		}

		guard let sample = Self.sampleBuffer(slices: slices, format: format) else {
			awaitingKeyframe = true
			return .needsKeyframe
		}

		let output = output
		let decodeStatus = OSStatusBox()
		let status = VTDecompressionSessionDecodeFrame(
			session,
			sampleBuffer: sample,
			flags: [],
			infoFlagsOut: nil
		) { status, _, imageBuffer, _, _ in
			decodeStatus.value = status
			if status == noErr, let imageBuffer {
				output(imageBuffer)
			}
		}
		guard status == noErr, decodeStatus.value == noErr else {
			awaitingKeyframe = true
			if status == kVTInvalidSessionErr {
				tearDownSession()
			}
			return .needsKeyframe
		}

		if hasIDR {
			awaitingKeyframe = false
		}
		return .decoded
	}

	public func invalidate() {
		tearDownSession()
		format = nil
		sps = nil
		pps = nil
	}

	private func tearDownSession() {
		if let session {
			VTDecompressionSessionInvalidate(session)
		}
		session = nil
	}

	private func configure(sps newSPS: Data, pps newPPS: Data) -> Bool {
		var description: CMVideoFormatDescription?
		let status = newSPS.withUnsafeBytes { (spsBytes: UnsafeRawBufferPointer) -> OSStatus in
			newPPS.withUnsafeBytes { (ppsBytes: UnsafeRawBufferPointer) -> OSStatus in
				guard let spsBase = spsBytes.bindMemory(to: UInt8.self).baseAddress,
					  let ppsBase = ppsBytes.bindMemory(to: UInt8.self).baseAddress else {
					return -1
				}

				let pointers = [spsBase, ppsBase]
				let sizes = [newSPS.count, newPPS.count]
				return CMVideoFormatDescriptionCreateFromH264ParameterSets(
					allocator: kCFAllocatorDefault,
					parameterSetCount: 2,
					parameterSetPointers: pointers,
					parameterSetSizes: sizes,
					nalUnitHeaderLength: 4,
					formatDescriptionOut: &description
				)
			}
		}
		guard status == noErr, let description else {
			return false
		}

		tearDownSession()
		let attributes: [CFString: Any] = [
			kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
			kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
		]
		var created: VTDecompressionSession?
		let sessionStatus = VTDecompressionSessionCreate(
			allocator: kCFAllocatorDefault,
			formatDescription: description,
			decoderSpecification: nil,
			imageBufferAttributes: attributes as CFDictionary,
			outputCallback: nil,
			decompressionSessionOut: &created
		)
		guard sessionStatus == noErr, let created else {
			return false
		}

		VTSessionSetProperty(created, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
		session = created
		format = description
		sps = newSPS
		pps = newPPS
		return true
	}

	/// One picture's slices as a length-prefixed sample.
	private static func sampleBuffer(slices: [Data], format: CMVideoFormatDescription) -> CMSampleBuffer? {
		var bytes = Data(capacity: slices.reduce(0) { $0 + $1.count + 4 })
		for slice in slices {
			withUnsafeBytes(of: UInt32(slice.count).bigEndian) { bytes.append(contentsOf: $0) }
			bytes.append(slice)
		}

		var block: CMBlockBuffer?
		guard CMBlockBufferCreateWithMemoryBlock(
			allocator: kCFAllocatorDefault,
			memoryBlock: nil,
			blockLength: bytes.count,
			blockAllocator: kCFAllocatorDefault,
			customBlockSource: nil,
			offsetToData: 0,
			dataLength: bytes.count,
			flags: kCMBlockBufferAssureMemoryNowFlag,
			blockBufferOut: &block
		) == noErr, let block else {
			return nil
		}

		let copied = bytes.withUnsafeBytes { buffer -> OSStatus in
			guard let base = buffer.baseAddress else {
				return -1
			}

			return CMBlockBufferReplaceDataBytes(
				with: base,
				blockBuffer: block,
				offsetIntoDestination: 0,
				dataLength: bytes.count
			)
		}
		guard copied == noErr else {
			return nil
		}

		var sample: CMSampleBuffer?
		var size = bytes.count
		guard CMSampleBufferCreateReady(
			allocator: kCFAllocatorDefault,
			dataBuffer: block,
			formatDescription: format,
			sampleCount: 1,
			sampleTimingEntryCount: 0,
			sampleTimingArray: nil,
			sampleSizeEntryCount: 1,
			sampleSizeArray: &size,
			sampleBufferOut: &sample
		) == noErr else {
			return nil
		}

		return sample
	}
}

/// The status a synchronous decode reports through its handler.
private final class OSStatusBox: @unchecked Sendable {
	var value: OSStatus = noErr
}
