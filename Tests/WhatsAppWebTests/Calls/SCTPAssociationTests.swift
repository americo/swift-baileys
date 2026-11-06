import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("SCTP association")
struct SCTPAssociationTests {
	/// Moves packets between the two ends until both are quiet. `drop` simulates loss on the wire.
	private func pump(
		_ client: inout SCTPAssociation,
		_ server: inout SCTPAssociation,
		now: UInt64,
		dropClientToServer: (Data) -> Bool = { _ in false }
	) {
		var moved = true
		while moved {
			moved = false
			while let packet = client.pollTransmit() {
				moved = true
				if !dropClientToServer(packet) {
					server.receive(packet, now: now)
				}
			}
			while let packet = server.pollTransmit() {
				moved = true
				client.receive(packet, now: now)
			}
		}
	}

	private func established() -> (SCTPAssociation, SCTPAssociation) {
		var client = SCTPAssociation(role: .client)
		var server = SCTPAssociation(role: .server)
		client.connect(now: 0)
		pump(&client, &server, now: 0)
		return (client, server)
	}

	private func messages(_ association: inout SCTPAssociation) -> [Data] {
		var result = [Data]()
		while let event = association.pollEvent() {
			if case let .message(_, _, data) = event {
				result.append(data)
			}
		}

		return result
	}

	@Test("CRC32c matches the standard check value")
	func crc32cMatchesStandardCheckValue() {
		#expect(SCTPAssociation.crc32c(Array("123456789".utf8)) == 0xe306_9283)
	}

	@Test("completes the four-way handshake")
	func completesHandshake() {
		var (client, server) = established()

		#expect(client.state == .established)
		#expect(server.state == .established)
		#expect(client.pollEvent() == .established)
		#expect(server.pollEvent() == .established)
		#expect(client.pollTimeout() == nil)
	}

	@Test("delivers messages in both directions")
	func deliversMessagesBothDirections() throws {
		var (client, server) = established()
		_ = client.pollEvent()
		_ = server.pollEvent()

		try client.send(Data([1, 2, 3]), now: 10)
		try server.send(Data([9, 8]), now: 10)
		pump(&client, &server, now: 10)

		#expect(messages(&server) == [Data([1, 2, 3])])
		#expect(messages(&client) == [Data([9, 8])])
		#expect(client.pollTimeout() == nil)
	}

	@Test("fragments and reassembles large messages")
	func fragmentsLargeMessages() throws {
		var (client, server) = established()
		_ = server.pollEvent()
		let big = Data((0..<5000).map { UInt8(truncatingIfNeeded: $0 &* 7) })

		try client.send(big, now: 5)
		pump(&client, &server, now: 5)

		#expect(messages(&server) == [big])
	}

	@Test("carries empty messages")
	func carriesEmptyMessages() throws {
		var (client, server) = established()
		_ = server.pollEvent()

		try client.send(Data(), now: 1)
		pump(&client, &server, now: 1)

		#expect(messages(&server) == [Data()])
	}

	@Test("abandons a lost chunk and skips it with FORWARD-TSN")
	func abandonsLostChunk() throws {
		var (client, server) = established()
		_ = server.pollEvent()
		var sent = 0

		try client.send(Data([1]), now: 100)
		try client.send(Data([2]), now: 100)
		try client.send(Data([3]), now: 100)
		pump(&client, &server, now: 100, dropClientToServer: { _ in
			sent += 1
			return sent == 1
		})

		// The first message never arrived; the later ones were delivered out of order.
		#expect(messages(&server) == [Data([2]), Data([3])])
		#expect(client.pollTimeout() != nil)

		client.handleTimeout(now: 100 + SCTPAssociation.retransmissionTimeoutMs)
		pump(&client, &server, now: 500)

		#expect(client.pollTimeout() == nil)
		try client.send(Data([4]), now: 600)
		pump(&client, &server, now: 600)
		#expect(messages(&server) == [Data([4])])
	}

	@Test("announces FORWARD-TSN in the supported extensions of INIT")
	func announcesForwardTSNInInit() throws {
		var client = SCTPAssociation(role: .client)
		client.connect(now: 0)
		let transmitted = client.pollTransmit()
		let packet = [UInt8](try #require(transmitted))

		// Common header 12, chunk header 4, fixed INIT fields 16, then the first parameter.
		#expect(Array(packet[32..<38]) == [0x80, 0x08, 0x00, 0x06, 130, 192])
		#expect(SCTPAssociation.checksumIsValid(packet))
	}

	@Test("ignores corrupted packets")
	func ignoresCorruptedPackets() throws {
		var (client, server) = established()
		_ = server.pollEvent()

		try client.send(Data([7]), now: 1)
		let transmitted = client.pollTransmit()
		var packet = try #require(transmitted)
		packet[packet.startIndex + packet.count - 1] ^= 0xff
		server.receive(packet, now: 1)

		#expect(messages(&server).isEmpty)
	}

	@Test("ignores packets with the wrong verification tag")
	func ignoresWrongVerificationTag() throws {
		var (client, server) = established()
		_ = server.pollEvent()
		var other = SCTPAssociation(role: .client)
		var otherServer = SCTPAssociation(role: .server)
		other.connect(now: 0)
		pump(&other, &otherServer, now: 0)
		try other.send(Data([5]), now: 1)

		while let packet = other.pollTransmit() {
			server.receive(packet, now: 1)
		}

		#expect(messages(&server).isEmpty)
		#expect(client.state == .established)
	}

	@Test("retransmits INIT until answered, then gives up")
	func retransmitsInitThenGivesUp() {
		var client = SCTPAssociation(role: .client)
		client.connect(now: 0)
		#expect(client.pollTransmit() != nil)

		client.handleTimeout(now: 1000)
		#expect(client.pollTransmit() != nil)

		var clock: UInt64 = 1000
		for _ in 0..<20 {
			clock += 10_000
			client.handleTimeout(now: clock)
		}

		var closed = false
		while let event = client.pollEvent() {
			if case .closed = event { closed = true }
		}
		#expect(closed)
		#expect(client.state == .closed)
	}

	@Test("closes when the peer aborts")
	func closesWhenPeerAborts() throws {
		var (client, server) = established()
		_ = client.pollEvent()
		_ = server.pollEvent()
		server.close()
		pump(&client, &server, now: 50)

		#expect(server.state == .closed)
		var closed = false
		while let event = client.pollEvent() {
			if case .closed = event { closed = true }
		}
		#expect(closed)
	}

	@Test("refuses to send before the association is established")
	func refusesToSendBeforeEstablished() {
		var client = SCTPAssociation(role: .client)

		#expect(throws: SCTPAssociation.SendError.notEstablished) {
			try client.send(Data([1]), now: 0)
		}
	}

	@Test("compares TSNs with serial arithmetic")
	func comparesTSNsWithSerialArithmetic() {
		#expect(SCTPAssociation.serialGreater(2, 1))
		#expect(!SCTPAssociation.serialGreater(1, 2))
		#expect(!SCTPAssociation.serialGreater(5, 5))
		#expect(SCTPAssociation.serialGreater(0, UInt32.max))
	}
}
