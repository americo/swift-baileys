import Foundation

actor TimedRequestCoordinator<Value: Sendable> {
	var pendingCount: Int {
		pending.count
	}

	private struct PendingRequest {
		let continuation: CheckedContinuation<Value, Error>
		let timeoutTask: Task<Void, Never>
	}

	private let duplicateError: @Sendable (String) -> any Error
	private let timeoutError: @Sendable (String) -> any Error
	private var pending: [String: PendingRequest] = [:]

	init(
		duplicateError: @escaping @Sendable (String) -> any Error,
		timeoutError: @escaping @Sendable (String) -> any Error
	) {
		self.duplicateError = duplicateError
		self.timeoutError = timeoutError
	}

	func perform(
		id: String,
		timeout: Duration,
		send: @Sendable @escaping () async throws -> Void
	) async throws -> Value {
		try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { continuation in
				register(id: id, timeout: timeout, continuation: continuation)
				Task.detached {
					do {
						try await send()
					} catch {
						await self.fail(id: id, error: error)
					}
				}
			}
		} onCancel: {
			Task.detached {
				await self.cancel(id: id)
			}
		}
	}

	func waitForResponse(id: String, timeout: Duration) async throws -> Value {
		try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { continuation in
				register(id: id, timeout: timeout, continuation: continuation)
			}
		} onCancel: {
			Task.detached {
				await self.cancel(id: id)
			}
		}
	}

	@discardableResult
	func resolve(id: String, value: Value) -> Bool {
		guard let request = pending.removeValue(forKey: id) else {
			return false
		}

		request.timeoutTask.cancel()
		request.continuation.resume(returning: value)
		return true
	}

	func failAll(error: Error) {
		let requests = pending
		pending.removeAll()

		for request in requests.values {
			request.timeoutTask.cancel()
			request.continuation.resume(throwing: error)
		}
	}

	private func register(
		id: String,
		timeout: Duration,
		continuation: CheckedContinuation<Value, Error>
	) {
		if pending[id] != nil {
			continuation.resume(throwing: duplicateError(id))
			return
		}

		let timeoutTask = Task.detached {
			do {
				try await Task.sleep(for: timeout)
				await self.fail(id: id, error: self.timeoutError(id))
			} catch {}
		}
		pending[id] = PendingRequest(continuation: continuation, timeoutTask: timeoutTask)
	}

	private func fail(id: String, error: Error) {
		guard let request = pending.removeValue(forKey: id) else {
			return
		}

		request.timeoutTask.cancel()
		request.continuation.resume(throwing: error)
	}

	private func cancel(id: String) {
		fail(id: id, error: CancellationError())
	}
}
