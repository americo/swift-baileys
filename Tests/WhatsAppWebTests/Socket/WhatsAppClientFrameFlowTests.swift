import Foundation
import Testing
@testable import WhatsAppWeb

/// Holds back the first frame, so anything not waiting for it overtakes it.
private actor SlowFirstFrameTransport: WhatsAppWebSocketTransport {
	private(set) var sentFrames: [Data] = []
	private var sendCount = 0
	private var inbound: [CheckedContinuation<Data?, Error>] = []

	func connect() async throws {}

	func send(_ data: Data) async throws {
		sendCount += 1
		if sendCount == 1 {
			try await Task.sleep(for: .milliseconds(100))
		}
		sentFrames.append(data)
	}

	func receive() async throws -> Data? {
		try await withCheckedThrowingContinuation { inbound.append($0) }
	}

	func close() async {
		inbound.forEach { $0.resume(returning: nil) }
		inbound = []
	}
}

private actor UploadResult {
	var error: String?
	var finished = false
	func finish(error: String?) {
		self.error = error
		finished = true
	}
}

/// Queries the server from inside a notification handler, as a real prekey upload does.
private final class QueryingUploader: PreKeyUploading, @unchecked Sendable {
	var client: WhatsAppClient?
	let result = UploadResult()

	func uploadPreKeys(count: Int) async throws {
		do {
			_ = try await client?.query(BinaryNode(tag: "iq", attrs: ["id": "upload-1", "type": "set"]), timeout: .seconds(3))
			await result.finish(error: nil)
		} catch {
			await result.finish(error: String(describing: error))
		}
	}
}

@Suite("WhatsApp client frame flow")
struct WhatsAppClientFrameFlowTests {
	@Test("frames reach the socket in the order they were numbered")
	func framesKeepTheirOrder() async throws {
		let transport = SlowFirstFrameTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		await client.attach(transport: transport)

		let first = Task { try await client.sendRawFrame(Data([1])) }
		try await Task.sleep(for: .milliseconds(10))
		try await client.sendRawFrame(Data([2]))
		try await first.value

		#expect(await transport.sentFrames == [Data([1]), Data([2])])
		await client.disconnect(reason: "test")
	}

	@Test("a handler can query the server without blocking the receive loop")
	func handlerQueryIsAnswered() async throws {
		let transport = MockWebSocketTransport()
		let uploader = QueryingUploader()
		let client = WhatsAppClient(transportFactory: { _ in transport }, preKeyUploader: uploader)
		uploader.client = client
		await client.attach(transport: transport)

		var codec = NoiseFrameCodec()
		let notification = BinaryNode(
			tag: "notification",
			attrs: ["from": "@s.whatsapp.net", "id": "encrypt-1", "type": "encrypt"],
			content: .nodes([BinaryNode(tag: "count", attrs: ["value": "1"])])
		)
		await transport.enqueueInbound(codec.encode(try BinaryNodeEncoder().encode(notification)))

		for _ in 0..<200 where await transport.sentFrames.isEmpty {
			try await Task.sleep(for: .milliseconds(5))
		}
		let reply = BinaryNode(tag: "iq", attrs: ["id": "upload-1", "type": "result"])
		await transport.enqueueInbound(codec.encode(try BinaryNodeEncoder().encode(reply)))

		for _ in 0..<200 where await !uploader.result.finished {
			try await Task.sleep(for: .milliseconds(5))
		}
		#expect(await uploader.result.finished)
		#expect(await uploader.result.error == nil)
		await client.disconnect(reason: "test")
	}
}
