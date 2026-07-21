import Foundation
@testable import WhatsAppWeb

actor MockProfileWebSocketTransport: WhatsAppWebSocketTransport {
	private var sentFrames: [Data] = []
	private var inboundContinuations: [CheckedContinuation<Data?, Error>] = []
	private var inboundFrames: [Data?] = []

	func connect() async throws {}

	func send(_ data: Data) async throws {
		sentFrames.append(data)
	}

	func receive() async throws -> Data? {
		try await withCheckedThrowingContinuation { continuation in
			if !inboundFrames.isEmpty {
				continuation.resume(returning: inboundFrames.removeFirst())
			} else {
				inboundContinuations.append(continuation)
			}
		}
	}

	func close() async {
		resumeInbound(nil)
	}

	func waitForSentNode(at index: Int = 0) async throws -> BinaryNode {
		while sentFrames.count <= index {
			try await Task.sleep(for: .milliseconds(1))
		}

		var codec = NoiseFrameCodec()
		return try BinaryNodeDecoder().decode(codec.decode(sentFrames[index])[0])
	}

	func sentFrameCount() -> Int {
		sentFrames.count
	}

	func enqueueInbound(_ node: BinaryNode) {
		let data = try! BinaryNodeEncoder().encode(node)
		var codec = NoiseFrameCodec()
		resumeInbound(codec.encode(data))
	}

	private func resumeInbound(_ data: Data?) {
		if inboundContinuations.isEmpty {
			inboundFrames.append(data)
		} else {
			inboundContinuations.removeFirst().resume(returning: data)
		}
	}
}
