import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client WAM")
struct WhatsAppClientWAMTests {
	@Test("sends WAM buffers through the stats IQ")
	func sendsWAMBuffersThroughStatsIQ() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.sendWAMBuffer(
				Data([0x57, 0x41, 0x4d, 0x05]),
				timestamp: 1_700_000_100,
				requestID: "wam-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request == BinaryNode(
			tag: "iq",
			attrs: [
				"to": "@s.whatsapp.net",
				"id": "wam-1",
				"xmlns": "w:stats"
			],
			content: .nodes([
				BinaryNode(
					tag: "add",
					attrs: ["t": "1700000100"],
					content: .data(Data([0x57, 0x41, 0x4d, 0x05]))
				)
			])
		))

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "wam-1", "type": "result"]))
		_ = try await task.value
	}

	@Test("encodes and sends WAM event inputs")
	func encodesAndSendsWAMEventInputs() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.sendWAM(
				WAMBinaryInfo(
					sequence: 9,
					events: [
						WAMEventInput(
							name: "WamClientErrors",
							props: [("isFromWamsys", .bool(false))]
						)
					]
				),
				events: [
					WAMEventDefinition(
						name: "WamClientErrors",
						id: 1144,
						weight: 1,
						props: ["isFromWamsys": 27]
					)
				],
				timestamp: 1_700_000_101,
				requestID: "wam-encoded-1"
			)
		}
		let request = try await transport.waitForSentNode()
		let add = try #require(request.firstChild(named: "add"))
		#expect(add.attrs["t"] == "1700000101")
		#expect(add.content == .data(Data([
			0x57, 0x41, 0x4d, 0x05, 0x01, 0x00, 0x09, 0x00,
			0x39, 0x78, 0x04, 0xff,
			0x16, 0x1b
		])))

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "wam-encoded-1", "type": "result"]))
		_ = try await task.value
	}

	@Test("sends and clears the actor WAM buffer")
	func sendsAndClearsTheActorWAMBuffer() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()
		await client.appendWAMEvent(WAMEventInput(
			name: "WamClientErrors",
			props: [("isFromWamsys", .bool(true))]
		))
		#expect(await client.wamBuffer.events.count == 1)

		let task = Task {
			try await client.sendBufferedWAM(
				events: [
					WAMEventDefinition(
						name: "WamClientErrors",
						id: 1144,
						weight: 1,
						props: ["isFromWamsys": 27]
					)
				],
				timestamp: 1_700_000_102,
				requestID: "wam-buffered-1"
			)
		}
		let request = try await transport.waitForSentNode()
		let add = try #require(request.firstChild(named: "add"))
		#expect(add.content == .data(Data([
			0x57, 0x41, 0x4d, 0x05, 0x01, 0x00, 0x00, 0x00,
			0x39, 0x78, 0x04, 0xff,
			0x26, 0x1b
		])))

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "wam-buffered-1", "type": "result"]))
		_ = try await task.value
		#expect(await client.wamBuffer.events.isEmpty)
	}

	@Test("can retain the actor WAM buffer after sending")
	func canRetainTheActorWAMBufferAfterSending() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()
		await client.replaceWAMBuffer(WAMBinaryInfo(
			sequence: 3,
			events: [
				WAMEventInput(
					name: "WamClientErrors",
					props: [("isFromWamsys", .bool(false))]
				)
			]
		))

		let task = Task {
			try await client.sendBufferedWAM(
				events: [
					WAMEventDefinition(
						name: "WamClientErrors",
						id: 1144,
						weight: 1,
						props: ["isFromWamsys": 27]
					)
				],
				timestamp: 1_700_000_103,
				requestID: "wam-buffered-retain-1",
				clearAfterSend: false
			)
		}
		_ = try await transport.waitForSentNode()
		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "wam-buffered-retain-1", "type": "result"]))
		_ = try await task.value

		#expect(await client.wamBuffer.sequence == 3)
		#expect(await client.wamBuffer.events.count == 1)
		await client.clearWAMBuffer()
		#expect(await client.wamBuffer.events.isEmpty)
	}

	@Test("sends buffered WAM with bundled Baileys definitions")
	func sendsBufferedWAMWithBundledDefinitions() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()
		await client.appendWAMEvent(WAMEventInput(
			name: "WamClientErrors",
			props: [("isFromWamsys", .bool(true))]
		))

		let task = Task {
			try await client.sendBufferedWAM(
				definitions: WAMDefinitions.web(),
				timestamp: 1_700_000_104,
				requestID: "wam-buffered-web-1"
			)
		}
		let request = try await transport.waitForSentNode()
		let add = try #require(request.firstChild(named: "add"))
		#expect(add.content == .data(Data([
			0x57, 0x41, 0x4d, 0x05, 0x01, 0x00, 0x00, 0x00,
			0x39, 0x78, 0x04, 0xff,
			0x26, 0x1b
		])))

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "wam-buffered-web-1", "type": "result"]))
		_ = try await task.value
		#expect(await client.wamBuffer.events.isEmpty)
	}

	@Test("sends buffered WAM with bundled definitions by default")
	func sendsBufferedWAMWithBundledDefinitionsByDefault() async throws {
		let transport = MockProfileWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()
		await client.appendWAMEvent(WAMEventInput(
			name: "WamClientErrors",
			props: [("isFromWamsys", .bool(false))]
		))

		let task = Task {
			try await client.sendBufferedWAM(
				timestamp: 1_700_000_105,
				requestID: "wam-buffered-default-1"
			)
		}
		let request = try await transport.waitForSentNode()
		let add = try #require(request.firstChild(named: "add"))
		#expect(add.content == .data(Data([
			0x57, 0x41, 0x4d, 0x05, 0x01, 0x00, 0x00, 0x00,
			0x39, 0x78, 0x04, 0xff,
			0x16, 0x1b
		])))

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "wam-buffered-default-1", "type": "result"]))
		_ = try await task.value
		#expect(await client.wamBuffer.events.isEmpty)
	}
}
