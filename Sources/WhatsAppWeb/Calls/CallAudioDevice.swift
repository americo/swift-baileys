import AVFoundation
import Foundation

public enum CallAudioDeviceError: Error, Equatable, Sendable {
	case formatUnavailable
	case inputUnavailable
	case alreadyRunning
}

/// Microphone and speaker for a call, on `AVAudioEngine`. Captured audio is converted to 16 kHz
/// mono and delivered in 60 ms frames; frames passed to `play` are queued on a player node.
///
/// Not covered by automated tests: it needs a real audio device and microphone permission.
public final class CallAudioDevice: @unchecked Sendable {
	private let engine = AVAudioEngine()
	private let player = AVAudioPlayerNode()
	private let lock = NSLock()
	private var pending = [Int16]()
	private var running = false
	private var onFrame: (([Int16]) -> Void)?
	private var converter: AVAudioConverter?

	private let playbackFormat: AVAudioFormat? = AVAudioFormat(
		commonFormat: .pcmFormatFloat32,
		sampleRate: CallAudioFormat.sampleRate,
		channels: 1,
		interleaved: false
	)

	public init() {}

	/// Starts capture and playback. `onFrame` receives each 960-sample microphone frame, on an
	/// audio thread. Enables the system's echo cancellation when available.
	public func start(onFrame: @escaping ([Int16]) -> Void) throws {
		lock.lock()
		defer { lock.unlock() }
		guard !running else {
			throw CallAudioDeviceError.alreadyRunning
		}
		guard let playbackFormat, let captureFormat = CallAudioFormat.pcm else {
			throw CallAudioDeviceError.formatUnavailable
		}

		let input = engine.inputNode
		// Voice processing gives acoustic echo cancellation; keep going without it if unsupported.
		try? input.setVoiceProcessingEnabled(true)

		let hardware = input.outputFormat(forBus: 0)
		guard hardware.sampleRate > 0, hardware.channelCount > 0 else {
			throw CallAudioDeviceError.inputUnavailable
		}
		guard let converter = AVAudioConverter(from: hardware, to: captureFormat) else {
			throw CallAudioDeviceError.formatUnavailable
		}

		self.converter = converter
		self.onFrame = onFrame
		pending.removeAll()

		engine.attach(player)
		engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
		input.installTap(onBus: 0, bufferSize: 2_048, format: hardware) { [weak self] buffer, _ in
			self?.capture(buffer, captureFormat: captureFormat)
		}

		engine.prepare()
		try engine.start()
		player.play()
		running = true
	}

	public func stop() {
		lock.lock()
		defer { lock.unlock() }
		guard running else {
			return
		}

		running = false
		engine.inputNode.removeTap(onBus: 0)
		player.stop()
		engine.stop()
		engine.detach(player)
		onFrame = nil
		converter = nil
		pending.removeAll()
	}

	/// Queues one decoded frame for playback.
	public func play(_ samples: [Int16]) {
		guard running, let playbackFormat, !samples.isEmpty,
			  let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(samples.count)),
			  let channel = buffer.floatChannelData?[0] else {
			return
		}

		buffer.frameLength = AVAudioFrameCount(samples.count)
		for index in samples.indices {
			channel[index] = Float(samples[index]) / 32_768
		}

		player.scheduleBuffer(buffer, completionHandler: nil)
	}

	private func capture(_ buffer: AVAudioPCMBuffer, captureFormat: AVAudioFormat) {
		lock.lock()
		guard running, let converter else {
			lock.unlock()
			return
		}

		let ratio = captureFormat.sampleRate / buffer.format.sampleRate
		let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
		guard let output = AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: capacity) else {
			lock.unlock()
			return
		}

		var supplied = false
		var error: NSError?
		converter.convert(to: output, error: &error) { _, status in
			if supplied {
				status.pointee = .noDataNow
				return nil
			}

			supplied = true
			status.pointee = .haveData
			return buffer
		}

		var frames = [[Int16]]()
		if error == nil, let channel = output.int16ChannelData?[0] {
			pending += UnsafeBufferPointer(start: channel, count: Int(output.frameLength))
			while pending.count >= CallAudioFormat.samplesPerFrame {
				frames.append(Array(pending.prefix(CallAudioFormat.samplesPerFrame)))
				pending.removeFirst(CallAudioFormat.samplesPerFrame)
			}
		}

		let callback = onFrame
		lock.unlock()
		frames.forEach { callback?($0) }
	}
}
