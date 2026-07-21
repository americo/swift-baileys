import Foundation

extension WhatsAppClient {
	public func waitForSocketOpen() throws {
		guard state == .connected else {
			throw WhatsAppClientError.notConnected
		}
	}

	public func sendRawMessage(_ data: Data) async throws {
		try waitForSocketOpen()
		try await sendRawFrame(outboundFrameCodec.encode(data))
	}

	public func waitForMessage(_ messageID: String, timeout: Duration = .seconds(60)) async throws -> BinaryNode? {
		do {
			return try await requestCoordinator.waitForResponse(id: messageID, timeout: timeout)
		} catch IQRequestCoordinatorError.timeout {
			return nil
		}
	}

	public func sendUnifiedSession(localDate: Date = Date()) async throws {
		guard state == .connected else {
			return
		}

		let dayMilliseconds: Int64 = 24 * 60 * 60 * 1_000
		let weekMilliseconds: Int64 = 7 * dayMilliseconds
		let offsetMilliseconds = 3 * dayMilliseconds
		let nowMilliseconds = Int64(localDate.timeIntervalSince1970 * 1_000) + serverTimeOffsetMilliseconds
		let sessionID = (nowMilliseconds + offsetMilliseconds) % weekMilliseconds

		try await sendNode(BinaryNode(
			tag: "ib",
			content: .nodes([
				BinaryNode(tag: "unified_session", attrs: ["id": String(sessionID)])
			])
		))
	}
}
