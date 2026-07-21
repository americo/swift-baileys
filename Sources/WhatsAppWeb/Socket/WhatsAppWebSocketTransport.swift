import Foundation

public protocol WhatsAppWebSocketTransport: Sendable {
	func connect() async throws
	func send(_ data: Data) async throws
	func receive() async throws -> Data?
	func close() async
}

public struct URLSessionWebSocketTransport: WhatsAppWebSocketTransport {
	private let task: URLSessionWebSocketTask

	public init(url: URL, session: URLSession = .shared) {
		self.task = session.webSocketTask(with: url)
	}

	public func connect() async throws {
		task.resume()
	}

	public func send(_ data: Data) async throws {
		try await task.send(.data(data))
	}

	public func receive() async throws -> Data? {
		switch try await task.receive() {
		case .data(let data):
			return data
		case .string(let string):
			return Data(string.utf8)
		@unknown default:
			return nil
		}
	}

	public func close() async {
		task.cancel(with: .normalClosure, reason: nil)
	}
}
