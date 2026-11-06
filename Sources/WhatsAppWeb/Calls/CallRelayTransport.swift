import Dispatch
import Foundation
import Network

public enum CallRelayTransportError: Error, Equatable, Sendable {
	case notConnected
	case failed(String)
	case closed(String)
}

/// Datagram path to a WhatsApp call relay: UDP, DTLS (client, certificates not verified because
/// media is authenticated by the call key), and an SCTP association whose stream 0 carries the
/// STUN, RTP and RTCP messages as binary chunks.
///
/// This mirrors the reverse-engineered WhatsApp Web transport. It has only been exercised in
/// memory against its own SCTP implementation; it has not been tried against a real relay.
public actor CallRelayTransport {
	public let host: String
	public let port: UInt16

	/// Messages received on the media stream, in arrival order.
	public nonisolated let messages: AsyncStream<Data>

	private let messageContinuation: AsyncStream<Data>.Continuation
	private let queue = DispatchQueue(label: "swift-baileys.call-relay")
	private var connection: NWConnection?
	private var association: SCTPAssociation
	private var established: CheckedContinuation<Void, Error>?
	private var pendingResult: Result<Void, Error>?
	private var timerTask: Task<Void, Never>?
	private var receiveTask: Task<Void, Never>?
	private var isClosed = false

	public init(host: String, port: UInt16) {
		self.host = host
		self.port = port
		self.association = SCTPAssociation(role: .client)
		var continuation: AsyncStream<Data>.Continuation!
		self.messages = AsyncStream { continuation = $0 }
		self.messageContinuation = continuation
	}

	/// Opens the DTLS session and the SCTP association; returns once the media stream is usable.
	public func connect(timeout: Duration = .seconds(10)) async throws {
		guard connection == nil, !isClosed else {
			throw CallRelayTransportError.failed("transport already used")
		}
		guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
			throw CallRelayTransportError.failed("invalid port")
		}

		let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: Self.parameters(queue: queue))
		self.connection = connection

		let datagrams = AsyncStream<Data> { continuation in
			Self.armReceive(connection, continuation)
		}
		receiveTask = Task { [weak self] in
			for await datagram in datagrams {
				await self?.handleDatagram(datagram)
			}
		}

		connection.stateUpdateHandler = { [weak self] state in
			Task { await self?.handleConnectionState(state) }
		}
		connection.start(queue: queue)

		let deadline = Task { [weak self] in
			try await Task.sleep(for: timeout)
			await self?.finishConnect(.failure(CallRelayTransportError.failed("relay handshake timed out")))
		}
		defer { deadline.cancel() }

		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			if let pendingResult {
				continuation.resume(with: pendingResult)
				return
			}

			established = continuation
		}

		timerTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: .milliseconds(50))
				await self?.tick()
			}
		}
	}

	/// Sends one STUN, RTP or RTCP message to the relay.
	public func send(_ message: Data) throws {
		guard !isClosed, connection != nil else {
			throw CallRelayTransportError.notConnected
		}

		do {
			try association.send(message, now: Self.nowMs())
		} catch {
			throw CallRelayTransportError.notConnected
		}
		flush()
	}

	public func close() {
		guard !isClosed else {
			return
		}

		isClosed = true
		association.close()
		flush()
		finishConnect(.failure(CallRelayTransportError.closed("closed locally")))
		timerTask?.cancel()
		receiveTask?.cancel()
		connection?.cancel()
		connection = nil
		messageContinuation.finish()
	}

	// MARK: Internals

	private static func parameters(queue: DispatchQueue) -> NWParameters {
		let tls = NWProtocolTLS.Options()
		sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .DTLSv12)
		// The relay certificate is not verified: media is authenticated by the call key instead.
		sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in
			complete(true)
		}, queue)
		return NWParameters(dtls: tls, udp: NWProtocolUDP.Options())
	}

	private static func armReceive(_ connection: NWConnection, _ continuation: AsyncStream<Data>.Continuation) {
		connection.receiveMessage { data, _, _, error in
			if let data, !data.isEmpty {
				continuation.yield(data)
			}
			if error != nil {
				continuation.finish()
				return
			}

			armReceive(connection, continuation)
		}
	}

	private static func nowMs() -> UInt64 {
		DispatchTime.now().uptimeNanoseconds / 1_000_000
	}

	private func handleConnectionState(_ state: NWConnection.State) {
		switch state {
		case .ready:
			guard !isClosed else {
				return
			}

			association.connect(now: Self.nowMs())
			flush()
		case let .failed(error):
			finishConnect(.failure(CallRelayTransportError.failed("dtls: \(error)")))
			shutDown(reason: "dtls failed: \(error)")
		case let .waiting(error):
			finishConnect(.failure(CallRelayTransportError.failed("dtls waiting: \(error)")))
		case .cancelled:
			finishConnect(.failure(CallRelayTransportError.closed("cancelled")))
		default:
			break
		}
	}

	private func handleDatagram(_ datagram: Data) {
		guard !isClosed else {
			return
		}

		association.receive(datagram, now: Self.nowMs())
		flush()
	}

	private func tick() {
		guard !isClosed else {
			return
		}

		association.handleTimeout(now: Self.nowMs())
		flush()
	}

	/// Sends what the association queued and reacts to what it reported.
	private func flush() {
		while let packet = association.pollTransmit() {
			connection?.send(content: packet, completion: .contentProcessed { _ in })
		}

		while let event = association.pollEvent() {
			switch event {
			case .established:
				finishConnect(.success(()))
			case let .message(_, _, data):
				messageContinuation.yield(data)
			case let .closed(reason):
				finishConnect(.failure(CallRelayTransportError.closed(reason)))
				shutDown(reason: reason)
				return
			}
		}
	}

	private func shutDown(reason: String) {
		guard !isClosed else {
			return
		}

		isClosed = true
		timerTask?.cancel()
		receiveTask?.cancel()
		connection?.cancel()
		connection = nil
		messageContinuation.finish()
	}

	private func finishConnect(_ result: Result<Void, Error>) {
		if let established {
			self.established = nil
			established.resume(with: result)
		} else if pendingResult == nil {
			pendingResult = result
		}
	}
}
