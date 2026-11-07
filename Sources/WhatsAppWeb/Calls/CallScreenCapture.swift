@preconcurrency import CoreMedia
@preconcurrency import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

/// What the user chose to share. It only ever gets read, so it can be handed between threads.
@available(macOS 14.0, *)
public struct CallScreenSelection: @unchecked Sendable {
	let filter: SCContentFilter
}

/// The system's own picker of what to share. Choosing there is what grants access to it, so sharing
/// needs no Screen Recording permission.
///
/// Not covered by automated tests: it needs someone to choose.
@available(macOS 14.0, *)
@MainActor
public final class CallScreenPicker: NSObject, SCContentSharingPickerObserver {
	private var pending: CheckedContinuation<CallScreenSelection?, Never>?
	/// Someone chose something else from the system's menu while sharing.
	public var onChange: (@Sendable (CallScreenSelection) -> Void)?

	public override init() {
		super.init()
	}

	/// Asks the user what to share. `nil` when they decided against it.
	public func pick() async -> CallScreenSelection? {
		finish(nil)

		let picker = SCContentSharingPicker.shared
		picker.add(self)
		picker.isActive = true
		return await withCheckedContinuation { continuation in
			pending = continuation
			picker.present()
		}
	}

	/// Leaves the system's picker as it was. Call it when sharing ends.
	public func deactivate() {
		finish(nil)
		onChange = nil
		let picker = SCContentSharingPicker.shared
		picker.remove(self)
		picker.isActive = false
	}

	private func finish(_ selection: CallScreenSelection?) {
		pending?.resume(returning: selection)
		pending = nil
	}

	private func choose(_ selection: CallScreenSelection) {
		if pending == nil {
			onChange?(selection)
		} else {
			finish(selection)
		}
	}

	public nonisolated func contentSharingPicker(
		_ picker: SCContentSharingPicker,
		didUpdateWith filter: SCContentFilter,
		for stream: SCStream?
	) {
		let chosen = CallScreenSelection(filter: filter)
		Task { @MainActor in self.choose(chosen) }
	}

	public nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
		Task { @MainActor in self.finish(nil) }
	}

	public nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
		WhatsAppLog.logger.error("screen picker failed: \(String(describing: error), privacy: .public)")
		Task { @MainActor in self.finish(nil) }
	}
}

/// What is on the screen as pictures for a call, in the same format the camera gives.
///
/// A still screen produces no pictures, and someone who just joined still has to see it, so the last one
/// goes out again now and then. That also gives a requested keyframe a picture to become.
///
/// Not covered by automated tests, apart from its sizing: it needs a screen and someone to choose one.
@available(macOS 14.0, *)
public final class CallScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
	/// Longer than this and the text is no sharper at the bitrates a call can give it.
	static let maxLongSide = 1280
	static let framesPerSecond: CMTimeScale = 15
	static let repeatInterval: TimeInterval = 0.5

	private let queue = DispatchQueue(label: "swift-baileys.call-screen", qos: .userInteractive)
	private let lock = NSLock()
	private var stream: SCStream?
	private var timer: DispatchSourceTimer?
	private var onFrame: (@Sendable (CVPixelBuffer, CMTime) -> Void)?
	private var onStopped: (@Sendable () -> Void)?
	private var filter: SCContentFilter
	private var lastPicture: CVPixelBuffer?
	private var lastDelivery: CMTime?

	/// `onFrame` runs on a private queue. `onStopped` says the system stopped it, as from its own menu.
	public init(
		selection: CallScreenSelection,
		onFrame: @escaping @Sendable (CVPixelBuffer, CMTime) -> Void,
		onStopped: @escaping @Sendable () -> Void
	) {
		self.filter = selection.filter
		self.onFrame = onFrame
		self.onStopped = onStopped
		super.init()
	}

	/// The size to capture at: the content's, within the limit, in the even numbers H.264 needs.
	public static func captureSize(content: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
		let width = max(content.width * scale, 2)
		let height = max(content.height * scale, 2)
		let shrink = min(1, CGFloat(maxLongSide) / max(width, height))
		func even(_ value: CGFloat) -> Int {
			max(Int((value * shrink / 2).rounded()) * 2, 2)
		}

		return (even(width), even(height))
	}

	private static func configuration(for filter: SCContentFilter) -> SCStreamConfiguration {
		let size = captureSize(content: filter.contentRect.size, scale: CGFloat(filter.pointPixelScale))
		let configuration = SCStreamConfiguration()
		configuration.width = size.width
		configuration.height = size.height
		configuration.minimumFrameInterval = CMTime(value: 1, timescale: framesPerSecond)
		configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
		configuration.showsCursor = true
		configuration.scalesToFit = true
		configuration.queueDepth = 5
		return configuration
	}

	public func start() async throws {
		let stream = SCStream(filter: filter, configuration: Self.configuration(for: filter), delegate: self)
		try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
		lock.withLock { self.stream = stream }
		try await stream.startCapture()

		let timer = DispatchSource.makeTimerSource(queue: queue)
		timer.schedule(deadline: .now() + Self.repeatInterval, repeating: Self.repeatInterval)
		timer.setEventHandler { [weak self] in self?.repeatLastPicture() }
		lock.withLock { self.timer = timer }
		timer.resume()
	}

	/// Shares what the user chose instead.
	public func update(selection: CallScreenSelection) {
		let current = lock.withLock {
			filter = selection.filter
			return stream
		}
		Task {
			try? await current?.updateContentFilter(selection.filter)
			try? await current?.updateConfiguration(Self.configuration(for: selection.filter))
		}
	}

	public func stop() {
		let (stream, timer) = lock.withLock {
			let held = (self.stream, self.timer)
			self.stream = nil
			self.timer = nil
			onFrame = nil
			onStopped = nil
			lastPicture = nil
			return held
		}
		timer?.cancel()
		Task { try? await stream?.stopCapture() }
	}

	public func stream(
		_ stream: SCStream,
		didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
		of type: SCStreamOutputType
	) {
		guard type == .screen, CMSampleBufferIsValid(sampleBuffer),
			  let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
				as? [[SCStreamFrameInfo: Any]],
			  let rawStatus = attachments.first?[.status] as? Int,
			  SCFrameStatus(rawValue: rawStatus) == .complete,
			  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
			return
		}

		deliver(pixelBuffer, at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
	}

	public func stream(_ stream: SCStream, didStopWithError error: any Error) {
		WhatsAppLog.logger.notice("screen capture stopped: \(String(describing: error), privacy: .public)")
		let onStopped = lock.withLock { self.onStopped }
		onStopped?()
	}

	private func deliver(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
		let onFrame = lock.withLock {
			lastPicture = onFrame == nil ? nil : pixelBuffer
			lastDelivery = time
			return self.onFrame
		}
		onFrame?(pixelBuffer, time)
	}

	private func repeatLastPicture() {
		let now = CMClockGetTime(CMClockGetHostTimeClock())
		let picture = lock.withLock { () -> CVPixelBuffer? in
			guard let lastDelivery, CMTimeGetSeconds(CMTimeSubtract(now, lastDelivery)) >= Self.repeatInterval else {
				return nil
			}

			return lastPicture
		}
		if let picture {
			deliver(picture, at: now)
		}
	}
}
