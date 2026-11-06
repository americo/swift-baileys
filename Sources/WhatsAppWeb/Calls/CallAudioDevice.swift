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
/// Prefers the system's echo cancellation (voice processing). Enabling it reconfigures the audio
/// device, which can stop the engine, so the engine restarts on a configuration change. A watchdog
/// also rebuilds it whenever microphone audio stops arriving, and gives up on echo cancellation
/// after a few attempts rather than leave the peer hearing nothing.
///
/// Not covered by automated tests: it needs a real audio device and microphone permission.
public final class CallAudioDevice: @unchecked Sendable {
	private static let captureWatchdog: DispatchTimeInterval = .seconds(1)
	private static let voiceProcessingAttempts = 3
	/// Below this a decoded sample is treated as silence, about -60 dB.
	private static let audibleSample = 32
	/// Checks in a row with audio queued but a silent mixer before the player is restarted.
	private static let silentOutputLimit = 2

	private let lock = NSLock()
	private var engine = AVAudioEngine()
	private var player = AVAudioPlayerNode()
	private var pending = [Int16]()
	private var running = false
	private var onFrame: (([Int16]) -> Void)?
	private var converter: AVAudioConverter?
	private var monoFormat: AVAudioFormat?
	/// Bumped per engine, so a tap or watchdog left over from a replaced engine does nothing.
	private var generation = 0
	/// Set by each tap, cleared by each watchdog check.
	private var capturedSinceCheck = false
	/// Audible samples were queued, or reached the mixer, since the last watchdog check.
	private var scheduledAudioSinceCheck = false
	private var mixerAudioSinceCheck = false
	private var silentOutputChecks = 0
	private var playedFrames = 0
	/// Loudest sample that reached the mixer, 0 to 1. Zero after a call means nothing was played.
	private(set) var maxPlaybackPeak: Float = 0
	private var attempts = 0
	private var configurationObserver: NSObjectProtocol?
	private var echoCancellationActive = false

	/// Whether the system's echo cancellation is on. Without it, speakers feed back into the call.
	public var isEchoCancellationActive: Bool {
		lock.lock()
		defer { lock.unlock() }
		return echoCancellationActive
	}

	private let playbackFormat: AVAudioFormat? = AVAudioFormat(
		commonFormat: .pcmFormatFloat32,
		sampleRate: CallAudioFormat.sampleRate,
		channels: 1,
		interleaved: false
	)

	public init() {}

	/// Starts capture and playback. `onFrame` receives each 960-sample microphone frame, on an
	/// audio thread.
	public func start(onFrame: @escaping ([Int16]) -> Void) throws {
		lock.lock()
		defer { lock.unlock() }
		guard !running else {
			throw CallAudioDeviceError.alreadyRunning
		}

		self.onFrame = onFrame
		attempts = 0
		running = true
		do {
			try startPreferredEngine()
		} catch {
			running = false
			self.onFrame = nil
			throw error
		}
	}

	public func stop() {
		lock.lock()
		guard running else {
			lock.unlock()
			return
		}

		WhatsAppLog.logger.notice("call audio: stopped played=\(self.playedFrames) outputPeak=\(self.maxPlaybackPeak) echoCancellation=\(self.echoCancellationActive)")
		running = false
		generation += 1
		onFrame = nil
		converter = nil
		monoFormat = nil
		pending.removeAll()
		removeConfigurationObserver()
		let engine = self.engine
		let player = self.player
		lock.unlock()

		// Outside the lock: stopping waits for a tap in flight, and the tap takes the lock.
		Self.tearDown(engine, player)
	}

	/// Queues one decoded frame for playback.
	public func play(_ samples: [Int16]) {
		guard let playbackFormat, !samples.isEmpty,
			  let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(samples.count)),
			  let channel = buffer.floatChannelData?[0] else {
			return
		}

		buffer.frameLength = AVAudioFrameCount(samples.count)
		for index in samples.indices {
			channel[index] = Float(samples[index]) / 32_768
		}

		lock.lock()
		defer { lock.unlock() }
		// A player being replaced by the watchdog has no engine to schedule on.
		guard running, player.engine != nil else {
			return
		}

		playedFrames += 1
		if samples.contains(where: { abs(Int($0)) > Self.audibleSample }) {
			scheduledAudioSinceCheck = true
		}
		player.scheduleBuffer(buffer, completionHandler: nil)
	}

	// MARK: Engine lifecycle

	/// Starts a new engine, with echo cancellation unless the attempts ran out. Call with the lock.
	private func startPreferredEngine() throws {
		generation += 1
		capturedSinceCheck = false
		defer { scheduleWatchdog() }
		if attempts < Self.voiceProcessingAttempts {
			attempts += 1
			do {
				try configureAndStart(voiceProcessing: true)
				echoCancellationActive = true
				return
			} catch {
				WhatsAppLog.logger.error("call audio: voice processing failed: \(String(describing: error), privacy: .public)")
				Self.tearDown(engine, player)
				attempts = Self.voiceProcessingAttempts
			}
		}

		// A node that had voice processing enabled cannot be reused, so this needs a new engine.
		engine = AVAudioEngine()
		player = AVAudioPlayerNode()
		do {
			try configureAndStart(voiceProcessing: false)
			echoCancellationActive = false
			WhatsAppLog.logger.notice("call audio: running without echo cancellation")
		} catch {
			Self.tearDown(engine, player)
			throw error
		}
	}

	private func scheduleWatchdog() {
		let expected = generation
		DispatchQueue.global().asyncAfter(deadline: .now() + Self.captureWatchdog) { [weak self] in
			self?.checkCapture(generation: expected)
		}
	}

	private func checkCapture(generation expected: Int) {
		lock.lock()
		guard running, generation == expected else {
			lock.unlock()
			return
		}

		recoverSilentOutput()
		if capturedSinceCheck {
			capturedSinceCheck = false
			scheduleWatchdog()
			lock.unlock()
			return
		}

		WhatsAppLog.logger.notice("call audio: microphone audio stopped, attempt \(self.attempts), restarting")
		generation += 1
		removeConfigurationObserver()
		let oldEngine = engine
		let oldPlayer = player
		engine = AVAudioEngine()
		player = AVAudioPlayerNode()
		lock.unlock()

		Self.tearDown(oldEngine, oldPlayer)

		lock.lock()
		defer { lock.unlock() }
		guard running else {
			return
		}

		do {
			try startPreferredEngine()
		} catch {
			WhatsAppLog.logger.error("call audio: microphone restart failed: \(String(describing: error), privacy: .public)")
		}
	}

	/// A player can report that it is playing while nothing reaches the mixer. Call with the lock.
	private func recoverSilentOutput() {
		defer {
			scheduledAudioSinceCheck = false
			mixerAudioSinceCheck = false
		}
		guard scheduledAudioSinceCheck, !mixerAudioSinceCheck else {
			silentOutputChecks = 0
			return
		}

		silentOutputChecks += 1
		guard silentOutputChecks >= Self.silentOutputLimit, engine.isRunning else {
			return
		}

		WhatsAppLog.logger.notice("call audio: queued audio is not reaching the output, restarting the player")
		silentOutputChecks = 0
		player.stop()
		player.play()
	}

	/// The audio device changed under the engine, which stops it. The graph is still valid unless
	/// the watchdog finds otherwise, so the cheap recovery comes first.
	private func handleConfigurationChange(generation expected: Int) {
		lock.lock()
		defer { lock.unlock() }
		guard running, generation == expected, !engine.isRunning else {
			return
		}

		WhatsAppLog.logger.notice("call audio: engine stopped by a configuration change, restarting it")
		do {
			// The player must be stopped first. Otherwise it claims to be playing after the restart
			// but renders nothing, and the call is silent on this side only.
			player.stop()
			try engine.start()
			player.play()
		} catch {
			// The watchdog rebuilds the engine when the audio does not come back.
			WhatsAppLog.logger.error("call audio: engine restart failed: \(String(describing: error), privacy: .public)")
		}
	}

	private func removeConfigurationObserver() {
		if let configurationObserver {
			NotificationCenter.default.removeObserver(configurationObserver)
		}
		configurationObserver = nil
	}

	private func configureAndStart(voiceProcessing: Bool) throws {
		guard let playbackFormat, let captureFormat = CallAudioFormat.pcm else {
			throw CallAudioDeviceError.formatUnavailable
		}

		let input = engine.inputNode
		if voiceProcessing {
			try input.setVoiceProcessingEnabled(true)
		}

		// With voice processing the tap sees several channels: the processed voice is the first.
		let hardware = input.outputFormat(forBus: 0)
		guard hardware.sampleRate > 0, hardware.channelCount > 0 else {
			throw CallAudioDeviceError.inputUnavailable
		}
		guard let mono = AVAudioFormat(
			commonFormat: .pcmFormatFloat32,
			sampleRate: hardware.sampleRate,
			channels: 1,
			interleaved: false
		), let output = AVAudioFormat(standardFormatWithSampleRate: hardware.sampleRate, channels: 2),
			let converter = AVAudioConverter(from: mono, to: captureFormat) else {
			throw CallAudioDeviceError.formatUnavailable
		}

		self.converter = converter
		monoFormat = mono
		pending.removeAll()

		engine.attach(player)
		engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
		// Voice processing leaves the output node's format unresolved. Without this explicit
		// connection at the hardware rate, the engine fails to initialize it with error -10875.
		engine.connect(engine.mainMixerNode, to: engine.outputNode, format: output)
		let tapGeneration = generation
		removeConfigurationObserver()
		configurationObserver = NotificationCenter.default.addObserver(
			forName: .AVAudioEngineConfigurationChange,
			object: engine,
			queue: nil
		) { [weak self] _ in
			self?.handleConfigurationChange(generation: tapGeneration)
		}
		input.installTap(onBus: 0, bufferSize: 2_048, format: hardware) { [weak self] buffer, _ in
			self?.capture(buffer, captureFormat: captureFormat, generation: tapGeneration)
		}

		engine.mainMixerNode.installTap(onBus: 0, bufferSize: 2_048, format: nil) { [weak self] buffer, _ in
			self?.observeOutput(buffer, generation: tapGeneration)
		}

		engine.prepare()
		try engine.start()
		player.play()
	}

	private func observeOutput(_ buffer: AVAudioPCMBuffer, generation tapGeneration: Int) {
		guard let channel = buffer.floatChannelData?[0] else {
			return
		}

		var peak: Float = 0
		for index in 0..<Int(buffer.frameLength) {
			peak = max(peak, abs(channel[index]))
		}

		lock.lock()
		defer { lock.unlock() }
		guard generation == tapGeneration else {
			return
		}

		maxPlaybackPeak = max(maxPlaybackPeak, peak)
		if peak > Float(Self.audibleSample) / 32_768 / 4 {
			mixerAudioSinceCheck = true
		}
	}

	private static func tearDown(_ engine: AVAudioEngine, _ player: AVAudioPlayerNode) {
		engine.inputNode.removeTap(onBus: 0)
		engine.mainMixerNode.removeTap(onBus: 0)
		player.stop()
		engine.stop()
		if player.engine != nil {
			engine.detach(player)
		}
	}

	// MARK: Capture

	private func capture(_ buffer: AVAudioPCMBuffer, captureFormat: AVAudioFormat, generation tapGeneration: Int) {
		lock.lock()
		guard running, generation == tapGeneration, let converter, let monoFormat,
			  let source = buffer.floatChannelData?[0],
			  let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameLength),
			  let target = mono.floatChannelData?[0] else {
			lock.unlock()
			return
		}

		capturedSinceCheck = true

		mono.frameLength = buffer.frameLength
		target.update(from: source, count: Int(buffer.frameLength))

		let ratio = captureFormat.sampleRate / monoFormat.sampleRate
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
			return mono
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
