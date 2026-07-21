import Foundation

public enum IQRequestCoordinatorError: Error, Equatable, Sendable {
	case duplicateRequest(id: String)
	case timeout(id: String)
}

public actor IQRequestCoordinator {
	public var pendingCount: Int {
		get async {
			await coordinator.pendingCount
		}
	}

	private let coordinator = TimedRequestCoordinator<BinaryNode>(
		duplicateError: { IQRequestCoordinatorError.duplicateRequest(id: $0) },
		timeoutError: { IQRequestCoordinatorError.timeout(id: $0) }
	)

	public init() {}

	public func perform(
		id: String,
		timeout: Duration,
		send: @Sendable @escaping () async throws -> Void
	) async throws -> BinaryNode {
		try await coordinator.perform(id: id, timeout: timeout, send: send)
	}

	public func waitForResponse(id: String, timeout: Duration) async throws -> BinaryNode {
		try await coordinator.waitForResponse(id: id, timeout: timeout)
	}

	public func receive(_ node: BinaryNode) async {
		_ = await resolve(node)
	}

	public func failAll(error: Error) async {
		await coordinator.failAll(error: error)
	}

	@discardableResult
	public func resolve(_ node: BinaryNode) async -> Bool {
		guard let id = node.attrs["id"] else {
			return false
		}

		return await coordinator.resolve(id: id, value: node)
	}
}
