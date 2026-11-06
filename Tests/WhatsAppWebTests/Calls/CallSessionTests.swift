import Foundation
import Testing
@testable import WhatsAppWeb

/// An in-memory relay: answers Allocate and forwards media from each leg to the other.
private actor FakeRelay {
	enum AllocateBehavior {
		case succeed
		case reject
		case ignore
	}

	private var continuations: [Int: AsyncStream<Data>.Continuation] = [:]
	private(set) var allocateRequests = 0
	private(set) var pings = 0
	var behavior: AllocateBehavior = .succeed

	func register(_ leg: Int, _ continuation: AsyncStream<Data>.Continuation) {
		continuations[leg] = continuation
	}

	func setBehavior(_ behavior: AllocateBehavior) {
		self.behavior = behavior
	}

	func receive(from leg: Int, _ message: Data) {
		if CallSTUN.isSTUN(message) {
			switch CallSTUN.messageType(message) {
			case CallSTUN.allocateRequest:
				allocateRequests += 1
				let transaction = CallSTUN.transactionID(message) ?? Data(count: 12)
				switch behavior {
				case .succeed:
					continuations[leg]?.yield(CallSTUN.encode(type: CallSTUN.allocateSuccess, transactionID: transaction))
				case .reject:
					let error = CallSTUN.attribute(CallSTUN.attributeErrorCode, Data([0, 0, 4, 1]))
					continuations[leg]?.yield(CallSTUN.encode(type: CallSTUN.allocateError, transactionID: transaction, attributes: error))
				case .ignore:
					break
				}
			case CallSTUN.whatsAppPing:
				pings += 1
			default:
				break
			}
			return
		}

		continuations[1 - leg]?.yield(message)
	}
}

private final class FakeLink: CallRelayLink, @unchecked Sendable {
	let messages: AsyncStream<Data>
	private let continuation: AsyncStream<Data>.Continuation
	private let relay: FakeRelay
	private let leg: Int
	private(set) var closed = false

	init(relay: FakeRelay, leg: Int) async {
		var continuation: AsyncStream<Data>.Continuation!
		self.messages = AsyncStream { continuation = $0 }
		self.continuation = continuation
		self.relay = relay
		self.leg = leg
		await relay.register(leg, continuation)
	}

	func open() async throws {}

	func send(_ message: Data) async throws {
		await relay.receive(from: leg, message)
	}

	func close() async {
		closed = true
		continuation.finish()
	}
}

@Suite("Call session")
struct CallSessionTests {
	private let callKey = Data((0..<32).map(UInt8.init))
	private let aliceLID = "111111111111111:0@lid"
	private let bobLID = "222222222222222:0@lid"

	private var relayData: CallRelayData {
		CallRelayData(
			relayKeyASCII: Data("relay-secret-key".utf8),
			relayTokens: [Data([1, 2, 3, 4])],
			authTokens: [],
			endpoints: [
				CallRelayEndpoint(
					relayID: 1,
					relayName: "gru1",
					tokenID: 0,
					authTokenID: 1,
					isFNA: false,
					ipv4Bytes: nil,
					addresses: [CallRelayAddress(protocolID: 0, ipv4: "157.240.226.133", ipv6: nil, port: 3478)],
					clientToRelayRTTMs: nil
				)
			]
		)
	}

	private func configuration(selfID: String, peerID: String) -> CallSession.Configuration {
		CallSession.Configuration(
			callID: "00112233445566778899AABBCCDDEEFF",
			selfParticipantID: selfID,
			peerParticipantID: peerID,
			callKey: callKey,
			relay: relayData
		)
	}

	private func tone(offset: Int) -> [Int16] {
		(0..<960).map { Int16(8_000 * sin(2 * .pi * 440 * Double($0 + offset) / 16_000)) }
	}

	@Test("allocates, then carries audio between two legs")
	func carriesAudioBetweenLegs() async throws {
		let relay = FakeRelay()
		let alice = try CallSession(
			configuration: configuration(selfID: aliceLID, peerID: bobLID),
			link: await FakeLink(relay: relay, leg: 0)
		)
		let bob = try CallSession(
			configuration: configuration(selfID: bobLID, peerID: aliceLID),
			link: await FakeLink(relay: relay, leg: 1)
		)
		try await alice.start()
		try await bob.start()

		let reader = Task { () -> [Int16] in
			var collected = [Int16]()
			for await frame in bob.receivedAudio {
				collected += frame
				if collected.count >= 960 * 5 { break }
			}

			return collected
		}

		for frame in 0..<6 {
			try await alice.sendAudio(tone(offset: frame * 960))
		}
		let received = await reader.value

		#expect(received.count >= 960 * 5)
		let energy = received.suffix(960 * 3).reduce(0.0) { $0 + Double($1) * Double($1) } / Double(960 * 3)
		#expect(energy > 1_000_000)
		#expect(await alice.framesSent == 6)
		#expect(await bob.framesReceived >= 5)
		#expect(await bob.packetsRejected == 0)
		await alice.stop()
		await bob.stop()
	}

	@Test("fails when the relay rejects the allocate")
	func failsWhenAllocateRejected() async throws {
		let relay = FakeRelay()
		await relay.setBehavior(.reject)
		let session = try CallSession(
			configuration: configuration(selfID: aliceLID, peerID: bobLID),
			link: await FakeLink(relay: relay, leg: 0)
		)

		await #expect(throws: CallSessionError.allocateRejected(401)) {
			try await session.start()
		}
	}

	@Test("retries the allocate while the relay is silent")
	func retriesAllocate() async throws {
		let relay = FakeRelay()
		await relay.setBehavior(.ignore)
		let session = try CallSession(
			configuration: configuration(selfID: aliceLID, peerID: bobLID),
			link: await FakeLink(relay: relay, leg: 0)
		)
		let starting = Task { try await session.start() }

		try await Task.sleep(for: .milliseconds(2_300))
		#expect(await relay.allocateRequests >= 2)
		await relay.setBehavior(.succeed)
		try await starting.value
		await session.stop()
	}

	@Test("cannot send before the session is running")
	func cannotSendBeforeRunning() async throws {
		let relay = FakeRelay()
		let session = try CallSession(
			configuration: configuration(selfID: aliceLID, peerID: bobLID),
			link: await FakeLink(relay: relay, leg: 0)
		)

		await #expect(throws: CallSessionError.notRunning) {
			try await session.sendAudio(tone(offset: 0))
		}
	}

	@Test("refuses configurations without a usable relay")
	func refusesUnusableRelay() throws {
		var noToken = relayData
		noToken.relayTokens = []
		var noKey = relayData
		noKey.relayKeyASCII = nil

		#expect(throws: CallSessionError.noRelay) {
			try CallSession(configuration: CallSession.Configuration(
				callID: "x", selfParticipantID: aliceLID, peerParticipantID: bobLID, callKey: callKey,
				relay: CallRelayData(relayTokens: [], authTokens: [], endpoints: [])
			))
		}
		#expect(throws: CallSessionError.missingRelayToken) {
			try CallSession(configuration: CallSession.Configuration(
				callID: "x", selfParticipantID: aliceLID, peerParticipantID: bobLID, callKey: callKey, relay: noToken
			))
		}
		#expect(throws: CallSessionError.missingIntegrityKey) {
			try CallSession(configuration: CallSession.Configuration(
				callID: "x", selfParticipantID: aliceLID, peerParticipantID: bobLID, callKey: callKey, relay: noKey
			))
		}
	}

	@Test("drops packets that fail authentication")
	func dropsForgedPackets() async throws {
		let relay = FakeRelay()
		let link = await FakeLink(relay: relay, leg: 0)
		let session = try CallSession(
			configuration: configuration(selfID: aliceLID, peerID: bobLID),
			link: link
		)
		try await session.start()

		let forged = CallRTPHeader(sequenceNumber: 1, timestamp: 0, ssrc: 9).encoded() + Data(count: 40)
		await relay.receive(from: 1, forged)
		try await Task.sleep(for: .milliseconds(100))

		#expect(await session.framesReceived == 0)
		#expect(await session.packetsRejected == 1)
		await session.stop()
	}
}
