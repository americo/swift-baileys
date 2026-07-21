import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("IQ request coordinator")
struct IQRequestCoordinatorTests {
	@Test("resolves a pending request with a matching stanza id")
	func resolvesMatchingResponse() async throws {
		let coordinator = IQRequestCoordinator()
		let task = Task {
			try await coordinator.waitForResponse(id: "abc", timeout: .seconds(1))
		}

		try await waitUntilPending(coordinator)
		await coordinator.receive(BinaryNode(tag: "iq", attrs: ["id": "abc", "type": "result"]))

		let response = try await task.value
		#expect(response.attrs["id"] == "abc")
		#expect(await coordinator.pendingCount == 0)
	}

	@Test("ignores responses for different stanza ids")
	func ignoresDifferentResponseIds() async throws {
		let coordinator = IQRequestCoordinator()
		let task = Task {
			try await coordinator.waitForResponse(id: "wanted", timeout: .seconds(1))
		}

		try await waitUntilPending(coordinator)
		await coordinator.receive(BinaryNode(tag: "iq", attrs: ["id": "other", "type": "result"]))
		await coordinator.receive(BinaryNode(tag: "iq", attrs: ["id": "wanted", "type": "result"]))

		let response = try await task.value
		#expect(response.attrs["id"] == "wanted")
		#expect(await coordinator.pendingCount == 0)
	}

	@Test("times out and removes the pending request")
	func timesOutAndCleansUp() async {
		let coordinator = IQRequestCoordinator()

		await #expect(throws: IQRequestCoordinatorError.timeout(id: "late")) {
			try await coordinator.waitForResponse(id: "late", timeout: .milliseconds(10))
		}

		#expect(await coordinator.pendingCount == 0)
	}

	private func waitUntilPending(_ coordinator: IQRequestCoordinator) async throws {
		while await coordinator.pendingCount == 0 {
			try await Task.sleep(for: .milliseconds(1))
		}
	}
}
