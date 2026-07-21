import Foundation
@testable import WhatsAppWeb

actor MockWebSocketTransport: WhatsAppWebSocketTransport {
	private(set) var connectCount = 0
	private(set) var closeCount = 0
	private(set) var sentFrames: [Data] = []
	var connectError: (any Error)?
	private var inboundContinuations: [CheckedContinuation<Data?, Error>] = []
	private var inboundResults: [Result<Data?, Error>] = []

	func connect() async throws {
		connectCount += 1
		if let connectError {
			throw connectError
		}
	}

	func setConnectError(_ error: any Error) {
		connectError = error
	}

	func send(_ data: Data) async throws {
		sentFrames.append(data)
	}

	func receive() async throws -> Data? {
		try await withCheckedThrowingContinuation { continuation in
			if !inboundResults.isEmpty {
				continuation.resume(with: inboundResults.removeFirst())
			} else {
				inboundContinuations.append(continuation)
			}
		}
	}

	func close() async {
		closeCount += 1
		resumeInbound(.success(nil))
	}

	func enqueueInbound(_ data: Data) {
		resumeInbound(.success(data))
	}

	func enqueueInboundClose() {
		resumeInbound(.success(nil))
	}

	func enqueueInboundError(_ error: Error) {
		resumeInbound(.failure(error))
	}

	private func resumeInbound(_ result: Result<Data?, Error>) {
		if !inboundContinuations.isEmpty {
			inboundContinuations.removeFirst().resume(with: result)
		} else {
			inboundResults.append(result)
		}
	}
}

enum MockReceiveError: Error {
	case broken
}
