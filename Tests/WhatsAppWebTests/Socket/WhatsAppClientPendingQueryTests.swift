import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client pending queries")
struct WhatsAppClientPendingQueryTests {
	@Test("manual disconnect fails pending queries immediately")
	func manualDisconnectFailsPendingQueriesImmediately() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.query(
				BinaryNode(tag: "iq", attrs: ["id": "pending-manual", "type": "get"]),
				timeout: .seconds(30)
			)
		}

		while await transport.sentFrames.isEmpty {
			try await Task.sleep(for: .milliseconds(1))
		}
		await client.disconnect(reason: "manual-close")

		await #expect(throws: WhatsAppClientError.disconnected(reason: "manual-close")) {
			try await task.value
		}
	}

	@Test("receive loop disconnect fails pending queries immediately")
	func receiveLoopDisconnectFailsPendingQueriesImmediately() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.query(
				BinaryNode(tag: "iq", attrs: ["id": "pending-receive", "type": "get"]),
				timeout: .seconds(30)
			)
		}

		while await transport.sentFrames.isEmpty {
			try await Task.sleep(for: .milliseconds(1))
		}
		await transport.enqueueInboundClose()

		await #expect(throws: WhatsAppClientError.disconnected(reason: "Connection Closed")) {
			try await task.value
		}
	}
}
