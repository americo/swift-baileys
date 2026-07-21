import Foundation

extension WhatsAppClient {
	public func appendWAMEvent(_ event: WAMEventInput) {
		wamBuffer.events.append(event)
	}

	public func replaceWAMBuffer(_ buffer: WAMBinaryInfo) {
		wamBuffer = buffer
	}

	public func clearWAMBuffer() {
		wamBuffer.events.removeAll()
	}

	@discardableResult
	public func sendWAMBuffer(
		_ buffer: Data,
		timestamp: Int64 = UnixTimestamp.seconds(),
		requestID: String? = nil,
		timeout: Duration = .seconds(60)
	) async throws -> BinaryNode {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		return try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"to": "@s.whatsapp.net",
				"id": id,
				"xmlns": "w:stats"
			],
			content: .nodes([
				BinaryNode(
					tag: "add",
					attrs: ["t": String(timestamp)],
					content: .data(buffer)
				)
			])
		), timeout: timeout)
	}

	@discardableResult
	public func sendWAM(
		_ binaryInfo: WAMBinaryInfo,
		timestamp: Int64 = UnixTimestamp.seconds(),
		requestID: String? = nil,
		timeout: Duration = .seconds(60)
	) async throws -> BinaryNode {
		let buffer = try WAMEncoder.encode(binaryInfo)
		return try await sendWAMBuffer(buffer, timestamp: timestamp, requestID: requestID, timeout: timeout)
	}

	@discardableResult
	public func sendWAM(
		_ binaryInfo: WAMBinaryInfo,
		events eventDefinitions: [WAMEventDefinition],
		globals globalDefinitions: [WAMGlobalDefinition] = [],
		timestamp: Int64 = UnixTimestamp.seconds(),
		requestID: String? = nil,
		timeout: Duration = .seconds(60)
	) async throws -> BinaryNode {
		let buffer = try WAMEncoder.encode(binaryInfo, events: eventDefinitions, globals: globalDefinitions)
		return try await sendWAMBuffer(buffer, timestamp: timestamp, requestID: requestID, timeout: timeout)
	}

	@discardableResult
	public func sendWAM(
		_ binaryInfo: WAMBinaryInfo,
		definitions: WAMDefinitions,
		timestamp: Int64 = UnixTimestamp.seconds(),
		requestID: String? = nil,
		timeout: Duration = .seconds(60)
	) async throws -> BinaryNode {
		let buffer = try WAMEncoder.encode(binaryInfo, definitions: definitions)
		return try await sendWAMBuffer(buffer, timestamp: timestamp, requestID: requestID, timeout: timeout)
	}

	@discardableResult
	public func sendBufferedWAM(
		timestamp: Int64 = UnixTimestamp.seconds(),
		requestID: String? = nil,
		timeout: Duration = .seconds(60),
		clearAfterSend: Bool = true
	) async throws -> BinaryNode {
		let currentBuffer = wamBuffer
		let response = try await sendWAM(
			currentBuffer,
			timestamp: timestamp,
			requestID: requestID,
			timeout: timeout
		)
		if clearAfterSend {
			wamBuffer.events.removeAll()
		}
		return response
	}

	@discardableResult
	public func sendBufferedWAM(
		events eventDefinitions: [WAMEventDefinition],
		globals globalDefinitions: [WAMGlobalDefinition] = [],
		timestamp: Int64 = UnixTimestamp.seconds(),
		requestID: String? = nil,
		timeout: Duration = .seconds(60),
		clearAfterSend: Bool = true
	) async throws -> BinaryNode {
		let currentBuffer = wamBuffer
		let response = try await sendWAM(
			currentBuffer,
			events: eventDefinitions,
			globals: globalDefinitions,
			timestamp: timestamp,
			requestID: requestID,
			timeout: timeout
		)
		if clearAfterSend {
			wamBuffer.events.removeAll()
		}
		return response
	}

	@discardableResult
	public func sendBufferedWAM(
		definitions: WAMDefinitions,
		timestamp: Int64 = UnixTimestamp.seconds(),
		requestID: String? = nil,
		timeout: Duration = .seconds(60),
		clearAfterSend: Bool = true
	) async throws -> BinaryNode {
		let currentBuffer = wamBuffer
		let response = try await sendWAM(
			currentBuffer,
			definitions: definitions,
			timestamp: timestamp,
			requestID: requestID,
			timeout: timeout
		)
		if clearAfterSend {
			wamBuffer.events.removeAll()
		}
		return response
	}
}
