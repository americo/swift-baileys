import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Media update coordinator")
struct MediaUpdateCoordinatorTests {
	@Test("resolves a pending media update by message id")
	func resolvesPendingMediaUpdateByMessageID() async throws {
		let coordinator = MediaUpdateCoordinator()
		let task = Task {
			try await coordinator.perform(id: "media-1", timeout: .seconds(1)) {}
		}

		try await waitUntilPending(coordinator)
		let update = MessageMediaUpdate(
			key: WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "media-1"),
			media: RetriedMedia(ciphertext: Data([1, 2]), iv: Data([3, 4]))
		)
		await coordinator.receive(update)

		#expect(try await task.value == update)
	}

	@Test("ignores media updates without a matching message id")
	func ignoresMediaUpdatesWithoutMatchingMessageID() async throws {
		let coordinator = MediaUpdateCoordinator()
		let task = Task {
			try await coordinator.perform(id: "wanted", timeout: .seconds(1)) {}
		}

		try await waitUntilPending(coordinator)
		await coordinator.receive(MessageMediaUpdate(
			key: WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "other")
		))
		let expected = MessageMediaUpdate(
			key: WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "wanted"),
			errorCode: 404,
			errorStatusCode: 404
		)
		await coordinator.receive(expected)

		#expect(try await task.value == expected)
	}

	@Test("times out pending media updates")
	func timesOutPendingMediaUpdates() async {
		let coordinator = MediaUpdateCoordinator()

		await #expect(throws: MediaUpdateCoordinatorError.timeout(id: "late")) {
			try await coordinator.perform(id: "late", timeout: .milliseconds(10)) {}
		}
	}

	@Test("fails all pending media updates")
	func failsAllPendingMediaUpdates() async throws {
		let coordinator = MediaUpdateCoordinator()
		let task = Task {
			try await coordinator.perform(id: "media-2", timeout: .seconds(1)) {}
		}

		try await waitUntilPending(coordinator)
		await coordinator.failAll(error: MediaUpdateCoordinatorTestError.disconnected)

		await #expect(throws: MediaUpdateCoordinatorTestError.disconnected) {
			try await task.value
		}
	}

	private func waitUntilPending(_ coordinator: MediaUpdateCoordinator) async throws {
		while await coordinator.pendingCount == 0 {
			try await Task.sleep(for: .milliseconds(1))
		}
	}
}

private enum MediaUpdateCoordinatorTestError: Error, Equatable {
	case disconnected
}
