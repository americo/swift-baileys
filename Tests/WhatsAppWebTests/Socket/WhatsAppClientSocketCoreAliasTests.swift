import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client socket core aliases")
struct WhatsAppClientSocketCoreAliasTests {
	@Test("Baileys waitForSocketOpen alias returns after connect")
	func baileysWaitForSocketOpenAliasReturnsAfterConnect() async throws {
		let client = WhatsAppClient(transportFactory: { _ in MockWebSocketTransport() })
		try await client.connect()

		try await client.waitForSocketOpen()
	}

	@Test("Baileys waitForSocketOpen alias fails before connect")
	func baileysWaitForSocketOpenAliasFailsBeforeConnect() async {
		let client = WhatsAppClient(transportFactory: { _ in MockWebSocketTransport() })

		await #expect(throws: WhatsAppClientError.notConnected) {
			try await client.waitForSocketOpen()
		}
	}

	@Test("Baileys sendRawMessage alias frames payload before sending")
	func baileysSendRawMessageAliasFramesPayloadBeforeSending() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		try await client.sendRawMessage(Data([1, 2, 3]))

		let sentFrame = await transport.sentFrames[0]
		#expect(sentFrame == Data([0, 0, 3, 1, 2, 3]))
	}

	@Test("Baileys waitForMessage alias resolves incoming nodes by id")
	func baileysWaitForMessageAliasResolvesIncomingNodesByID() async throws {
		let client = WhatsAppClient(transportFactory: { _ in MockWebSocketTransport() })
		let task = Task {
			try await client.waitForMessage("msg-wait", timeout: .seconds(1))
		}
		while await client.requestCoordinator.pendingCount == 0 {
			try await Task.sleep(for: .milliseconds(1))
		}

		await client.handleIncomingNode(BinaryNode(tag: "iq", attrs: ["id": "msg-wait", "type": "result"]))

		#expect(try await task.value == BinaryNode(tag: "iq", attrs: ["id": "msg-wait", "type": "result"]))
	}

	@Test("Baileys waitForMessage alias returns nil on timeout")
	func baileysWaitForMessageAliasReturnsNilOnTimeout() async throws {
		let client = WhatsAppClient(transportFactory: { _ in MockWebSocketTransport() })

		let result = try await client.waitForMessage("missing-message", timeout: .milliseconds(1))

		#expect(result == nil)
	}

	@Test("Baileys waitForMessage alias throws when disconnected")
	func baileysWaitForMessageAliasThrowsWhenDisconnected() async throws {
		let client = WhatsAppClient(transportFactory: { _ in MockWebSocketTransport() })
		let task = Task {
			try await client.waitForMessage("pending-message", timeout: .seconds(30))
		}
		while await client.requestCoordinator.pendingCount == 0 {
			try await Task.sleep(for: .milliseconds(1))
		}

		await client.disconnect(reason: "manual-close")

		await #expect(throws: WhatsAppClientError.disconnected(reason: "manual-close")) {
			try await task.value
		}
	}

	@Test("Baileys sendUnifiedSession alias sends weekly session telemetry")
	func baileysSendUnifiedSessionAliasSendsWeeklySessionTelemetry() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()
		await client.updateServerTimeOffset(
			BinaryNode(tag: "ib", attrs: ["t": "100"]),
			localDate: Date(timeIntervalSince1970: 0)
		)

		try await client.sendUnifiedSession(localDate: Date(timeIntervalSince1970: 2))

		let sentFrame = await transport.sentFrames[0]
		var codec = NoiseFrameCodec()
		let sentNode = try BinaryNodeDecoder().decode(codec.decode(sentFrame)[0])
		#expect(sentNode.tag == "ib")
		#expect(sentNode.firstChild(named: "unified_session")?.attrs["id"] == "259302000")
	}

	@Test("Baileys sendUnifiedSession alias skips closed sockets")
	func baileysSendUnifiedSessionAliasSkipsClosedSockets() async throws {
		let transport = MockWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })

		try await client.sendUnifiedSession(localDate: Date(timeIntervalSince1970: 0))

		#expect(await transport.sentFrames.isEmpty)
	}
}
