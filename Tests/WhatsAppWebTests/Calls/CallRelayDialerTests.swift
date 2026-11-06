import Foundation
import Testing
@testable import WhatsAppWeb

/// A link whose `open` succeeds, fails, or waits until the link is closed.
private actor ScriptedLink: CallRelayLink {
	enum Behavior {
		case succeed
		case fail
		case hang
	}

	nonisolated let messages: AsyncStream<Data>
	private let continuation: AsyncStream<Data>.Continuation
	private let behavior: Behavior
	private var waiter: CheckedContinuation<Void, Error>?
	private(set) var closed = false
	private(set) var sent = [Data]()

	init(_ behavior: Behavior) {
		self.behavior = behavior
		var continuation: AsyncStream<Data>.Continuation!
		self.messages = AsyncStream { continuation = $0 }
		self.continuation = continuation
	}

	func open() async throws {
		switch behavior {
		case .succeed:
			return
		case .fail:
			throw CallRelayTransportError.failed("scripted")
		case .hang:
			try await withCheckedThrowingContinuation { waiter = $0 }
		}
	}

	func send(_ message: Data) async throws {
		sent.append(message)
	}

	func close() async {
		closed = true
		continuation.finish()
		waiter?.resume(throwing: CallRelayTransportError.closed("closed"))
		waiter = nil
	}

	func deliver(_ message: Data) {
		continuation.yield(message)
	}
}

@Suite("Call relay dialer")
struct CallRelayDialerTests {
	@Test("dials the advertised port and the web client port")
	func candidatePorts() {
		#expect(CallRelayDialer.candidatePorts(advertised: 3478) == [3478, 3480])
		#expect(CallRelayDialer.candidatePorts(advertised: 3480) == [3480])
	}

	@Test("keeps the port that answers when the other is silent")
	func keepsTheAnsweringPort() async throws {
		let silent = ScriptedLink(.hang)
		let answering = ScriptedLink(.succeed)
		let dialer = CallRelayDialer(candidates: [silent, answering])

		try await dialer.open()
		try await dialer.send(Data([1]))

		#expect(await silent.closed)
		#expect(await silent.sent.isEmpty)
		#expect(await answering.sent == [Data([1])])
		#expect(await !answering.closed)
		await dialer.close()
		#expect(await answering.closed)
	}

	@Test("survives one port failing outright")
	func survivesOneFailure() async throws {
		let failing = ScriptedLink(.fail)
		let answering = ScriptedLink(.succeed)
		let dialer = CallRelayDialer(candidates: [failing, answering])

		try await dialer.open()
		try await dialer.send(Data([2]))

		#expect(await answering.sent == [Data([2])])
		await dialer.close()
	}

	@Test("fails only when every port failed")
	func failsWhenAllFail() async {
		let dialer = CallRelayDialer(candidates: [ScriptedLink(.fail), ScriptedLink(.fail)])

		await #expect(throws: CallRelayTransportError.self) {
			try await dialer.open()
		}
		await #expect(throws: CallRelayTransportError.notConnected) {
			try await dialer.send(Data([3]))
		}
	}

	@Test("forwards the messages of the port it kept")
	func forwardsMessages() async throws {
		let answering = ScriptedLink(.succeed)
		let dialer = CallRelayDialer(candidates: [answering])
		try await dialer.open()

		await answering.deliver(Data([9]))
		var iterator = dialer.messages.makeAsyncIterator()
		let message = await iterator.next()

		#expect(message == Data([9]))
		await dialer.close()
	}
}
