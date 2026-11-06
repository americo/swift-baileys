import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Call relay transport")
struct CallRelayTransportTests {
	@Test("refuses to send before connecting")
	func refusesToSendBeforeConnecting() async {
		let transport = CallRelayTransport(host: "127.0.0.1", port: 3478)

		await #expect(throws: CallRelayTransportError.notConnected) {
			try await transport.send(Data([1]))
		}
	}

	@Test("finishes the message stream when closed")
	func finishesMessageStreamWhenClosed() async {
		let transport = CallRelayTransport(host: "127.0.0.1", port: 3478)
		await transport.close()

		var received = [Data]()
		for await message in transport.messages {
			received.append(message)
		}

		#expect(received.isEmpty)
	}

	@Test("cannot connect after close")
	func cannotConnectAfterClose() async {
		let transport = CallRelayTransport(host: "127.0.0.1", port: 3478)
		await transport.close()

		await #expect(throws: CallRelayTransportError.self) {
			try await transport.connect(timeout: .milliseconds(200))
		}
	}
}
