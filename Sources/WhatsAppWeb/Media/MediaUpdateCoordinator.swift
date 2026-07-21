import Foundation

enum MediaUpdateCoordinatorError: Error, Equatable, Sendable {
	case duplicateRequest(id: String)
	case timeout(id: String)
}

actor MediaUpdateCoordinator {
	var pendingCount: Int {
		get async {
			await coordinator.pendingCount
		}
	}

	private let coordinator = TimedRequestCoordinator<MessageMediaUpdate>(
		duplicateError: { MediaUpdateCoordinatorError.duplicateRequest(id: $0) },
		timeoutError: { MediaUpdateCoordinatorError.timeout(id: $0) }
	)

	func perform(
		id: String,
		timeout: Duration,
		send: @Sendable @escaping () async throws -> Void
	) async throws -> MessageMediaUpdate {
		try await coordinator.perform(id: id, timeout: timeout, send: send)
	}

	func receive(_ update: MessageMediaUpdate) async {
		guard let id = update.key.id else {
			return
		}

		await coordinator.resolve(id: id, value: update)
	}

	func failAll(error: Error) async {
		await coordinator.failAll(error: error)
	}
}
