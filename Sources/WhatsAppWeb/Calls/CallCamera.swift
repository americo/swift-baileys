@preconcurrency import AVFoundation
import Foundation

public enum CallCameraError: Error, Equatable, Sendable {
	case noCamera
	case configurationFailed
}

/// The camera for a call, on `AVCaptureSession`: 720p when the camera has it, delivering pictures on
/// a private queue, dropping the ones that arrive late rather than falling behind.
///
/// Not covered by automated tests: it needs a real camera and permission to use it.
public final class CallCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
	/// What a preview layer attaches to. Valid from `init`, carrying pictures once started.
	public let session = AVCaptureSession()

	private let queue = DispatchQueue(label: "swift-baileys.call-camera", qos: .userInteractive)
	private let lock = NSLock()
	private var onFrame: (@Sendable (CVPixelBuffer, CMTime) -> Void)?

	/// `onFrame` runs on the camera's queue.
	public init(onFrame: @escaping @Sendable (CVPixelBuffer, CMTime) -> Void) throws {
		self.onFrame = onFrame
		super.init()

		guard let device = AVCaptureDevice.default(for: .video) else {
			throw CallCameraError.noCamera
		}
		guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
			throw CallCameraError.configurationFailed
		}

		let output = AVCaptureVideoDataOutput()
		output.alwaysDiscardsLateVideoFrames = true
		output.videoSettings = [
			kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
		]
		output.setSampleBufferDelegate(self, queue: queue)
		guard session.canAddOutput(output) else {
			throw CallCameraError.configurationFailed
		}

		session.beginConfiguration()
		session.addInput(input)
		session.addOutput(output)
		for preset in [AVCaptureSession.Preset.hd1280x720, .vga640x480] where session.canSetSessionPreset(preset) {
			session.sessionPreset = preset
			break
		}
		session.commitConfiguration()
	}

	/// Blocks while the camera starts, so call it off the main thread.
	public func start() {
		if !session.isRunning {
			session.startRunning()
		}
	}

	/// Stops the camera and its pictures, which may still be in flight for a moment.
	public func stop() {
		lock.lock()
		onFrame = nil
		lock.unlock()
		if session.isRunning {
			session.stopRunning()
		}
	}

	public func captureOutput(
		_ output: AVCaptureOutput,
		didOutput sampleBuffer: CMSampleBuffer,
		from connection: AVCaptureConnection
	) {
		guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
			return
		}

		lock.lock()
		let onFrame = onFrame
		lock.unlock()
		onFrame?(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
	}
}
