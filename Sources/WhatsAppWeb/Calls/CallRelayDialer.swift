import Foundation

/// Dials a relay on several links at once and keeps the first that connects.
///
/// The port a relay advertises goes unanswered for some relays, which would cost the whole
/// connect timeout and fail the call. The web client port is dialled beside it, so one silent port
/// costs nothing. Only the dial changes: the Allocate still names the advertised endpoint.
public actor CallRelayDialer: CallRelayLink {
	public nonisolated let messages: AsyncStream<Data>

	private let continuation: AsyncStream<Data>.Continuation
	private let candidates: [any CallRelayLink]
	private var winner: (any CallRelayLink)?
	private var pump: Task<Void, Never>?

	/// The advertised port first, then the web client port unless they are the same.
	public static func candidatePorts(advertised: UInt16) -> [UInt16] {
		advertised == CallRelayData.webClientPort ? [advertised] : [advertised, CallRelayData.webClientPort]
	}

	public init(host: String, advertisedPort: UInt16) {
		self.init(candidates: Self.candidatePorts(advertised: advertisedPort).map {
			CallRelayTransport(host: host, port: $0)
		})
	}

	init(candidates: [any CallRelayLink]) {
		self.candidates = candidates
		var continuation: AsyncStream<Data>.Continuation!
		self.messages = AsyncStream { continuation = $0 }
		self.continuation = continuation
	}

	/// Returns once one candidate connected, and fails only when all of them did.
	public func open() async throws {
		let links = candidates
		let chosen = try await withThrowingTaskGroup(of: Int.self) { group in
			for (index, link) in links.enumerated() {
				group.addTask {
					try await link.open()
					return index
				}
			}

			var lastError: Error?
			while !group.isEmpty {
				do {
					if let index = try await group.next() {
						// Closing is what releases the losers' dials, which the group waits for.
						for (other, link) in links.enumerated() where other != index {
							await link.close()
						}
						group.cancelAll()
						return index
					}
				} catch {
					lastError = error
				}
			}

			throw lastError ?? CallRelayTransportError.notConnected
		}

		let link = links[chosen]
		winner = link
		let continuation = self.continuation
		pump = Task {
			for await message in link.messages {
				continuation.yield(message)
			}
			continuation.finish()
		}
	}

	public func sendPressure() async -> SCTPAssociation.SendPressure? {
		await winner?.sendPressure()
	}

	public func send(_ message: Data) async throws {
		guard let winner else {
			throw CallRelayTransportError.notConnected
		}

		try await winner.send(message)
	}

	public func close() async {
		pump?.cancel()
		pump = nil
		for link in candidates {
			await link.close()
		}
		continuation.finish()
	}
}
