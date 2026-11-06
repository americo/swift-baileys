import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Call RTP and allocate")
struct CallRTPTests {
	private let callKey = Data(hex: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
	private let selfLID = "111111111111111:0@lid"
	private let peerLID = "222222222222222:0@lid"

	// MARK: SSRC

	@Test("derives SSRCs matching the reference vectors")
	func derivesSSRCs() {
		let callID = "00112233445566778899AABBCCDDEEFF"

		#expect(CallRelayAllocate.ssrc(callID: callID, participantID: peerLID, slot: 0) == 1_805_509_457)
		#expect(CallRelayAllocate.ssrc(callID: callID, participantID: peerLID, slot: 1) == 2_479_325_408)
		#expect(CallRelayAllocate.ssrc(callID: "CALL-ID-0001", participantID: "12345:0@lid", slot: 2) == 0xf8d7_0484)
	}

	@Test("builds an allocate request matching the reference vector")
	func buildsAllocateRequest() throws {
		let request = try #require(CallRelayAllocate.request(
			transactionID: Data(hex: "a0a1a2a3a4a5a6a7a8a9aaab"),
			relayToken: Data(hex: "1020304050607080"),
			relayIPv4: "157.240.226.133",
			relayPort: 3478,
			integrityKey: Data(hex: "30313233343536373839616263646566"),
			callID: "CALL-ID-0001",
			participantID: "12345:0@lid"
		))

		#expect(CallSTUN.messageType(request) == CallSTUN.allocateRequest)
		let attributes = CallSTUN.attributes(of: request)
		#expect(attributes.map(\.type) == [0x4000, 0x4024, 0x0016, 0x0008])
		#expect(attributes[1].value == CallRelayAllocate.streamDescriptors(callID: "CALL-ID-0001", participantID: "12345:0@lid"))
		#expect(attributes[2].value == Data([0x00, 0x01]) + Data(hex: "2c84bce246c7"))
	}

	/// The reference vector's descriptors were generated with other call and participant ids, so
	/// the bytes are compared by shape: nine streams in this order, the same fields, and each SSRC
	/// derived for its own slot.
	@Test("stream descriptors follow the reference layout")
	func streamDescriptorsFollowReferenceLayout() {
		let callID = "CALL-ID-0001"
		let participant = "12345:0@lid"
		let descriptors = Self.decodeDescriptors(CallRelayAllocate.streamDescriptors(callID: callID, participantID: participant))

		#expect(descriptors.map(\.stream) == [0, 0, 0, 1, 1, 1, 2, 2, 2])
		#expect(descriptors.map(\.subType) == [0, 1, 2, 0, 1, 2, 0, 1, 2])
		#expect(descriptors.map(\.ssrc) == [0, 1, 4, 2, 3, 5, 7, 8, 6].map {
			UInt64(CallRelayAllocate.ssrc(callID: callID, participantID: participant, slot: $0))
		})
		// Zero-valued fields are omitted on the wire rather than encoded.
		let firstField = CallRelayAllocate.streamDescriptors(callID: callID, participantID: participant).first
		#expect(firstField == 0x0a)
	}

	private static func decodeDescriptors(_ data: Data) -> [(stream: UInt64, subType: UInt64, ssrc: UInt64)] {
		let bytes = [UInt8](data)
		func varint(_ buffer: [UInt8], _ offset: inout Int) -> UInt64 {
			var result: UInt64 = 0
			var shift: UInt64 = 0
			while true {
				let byte = buffer[offset]
				offset += 1
				result |= UInt64(byte & 0x7f) << shift
				shift += 7
				if byte < 0x80 { return result }
			}
		}

		var offset = 0
		var result = [(stream: UInt64, subType: UInt64, ssrc: UInt64)]()
		while offset < bytes.count {
			_ = varint(bytes, &offset)
			let length = Int(varint(bytes, &offset))
			let inner = Array(bytes[offset..<offset + length])
			offset += length
			var position = 0
			var fields = [UInt64: UInt64]()
			while position < inner.count {
				let tag = varint(inner, &position)
				fields[tag >> 3] = varint(inner, &position)
			}
			result.append((fields[1] ?? 0, fields[2] ?? 0, fields[3] ?? 0))
		}

		return result
	}

	// MARK: Header

	@Test("encodes the 16-byte speech header")
	func encodesSpeechHeader() {
		let header = CallRTPHeader(marker: true, sequenceNumber: 1, timestamp: 0, ssrc: 0x1234_5678)

		#expect(header.encoded() == Data(hex: "90f800010000000012345678debe0000"))
	}

	@Test("encodes the 20-byte header with an extension word")
	func encodesExtensionHeader() {
		let header = CallRTPHeader(sequenceNumber: 2, timestamp: 0x140, ssrc: 0x1234_5678, extensionWord: 0x3001_0000)

		#expect(header.encoded() == Data(hex: "907800020000014012345678debe000130010000"))
		#expect(CallRTPHeader.parse(header.encoded()) == header)
	}

	@Test("parses headers and rejects non-RTP")
	func parsesHeaders() {
		let header = CallRTPHeader(marker: true, payloadType: 111, sequenceNumber: 65_535, timestamp: 9, ssrc: 7)

		#expect(CallRTPHeader.parse(header.encoded()) == header)
		#expect(CallRTPHeader.length(of: header.encoded()) == 16)
		#expect(CallRTPHeader.parse(Data(count: 4)) == nil)
		#expect(CallRTPHeader.parse(Data([0x40] + [UInt8](repeating: 0, count: 15))) == nil)
	}

	// MARK: Pipeline

	private func pipelines() throws -> (CallAudioPipeline, CallAudioPipeline) {
		let alice = try CallAudioPipeline(callKey: callKey, selfParticipantID: selfLID, peerParticipantID: peerLID, ssrc: 0xaaaa)
		let bob = try CallAudioPipeline(callKey: callKey, selfParticipantID: peerLID, peerParticipantID: selfLID, ssrc: 0xbbbb)
		return (alice, bob)
	}

	@Test("a protected packet decrypts on the other side")
	func roundtripsAudio() throws {
		var (alice, bob) = try pipelines()
		let frame = Data((0..<120).map { UInt8(truncatingIfNeeded: $0) })

		let packet = try alice.protect(frame)
		let received = try bob.unprotect(packet)

		#expect(received.payload == frame)
		#expect(received.header.sequenceNumber == 1)
		#expect(received.header.timestamp == 0)
		#expect(received.header.ssrc == 0xaaaa)
		#expect(received.header.payloadType == 120)
		#expect(packet.count == 16 + frame.count + 4)
	}

	@Test("sequence and timestamp advance per packet")
	func advancesSequenceAndTimestamp() throws {
		var (alice, bob) = try pipelines()

		_ = try alice.protect(Data([1]))
		let second = try bob.unprotect(alice.protect(Data([2])))

		#expect(second.header.sequenceNumber == 2)
		#expect(second.header.timestamp == 960)
	}

	@Test("rejects tampered and foreign packets without advancing state")
	func rejectsTamperedPackets() throws {
		var (alice, bob) = try pipelines()
		var packet = try alice.protect(Data([1, 2, 3]))
		packet[packet.startIndex + 17] ^= 0x01

		#expect(throws: CallAudioPipeline.ReceiveError.authenticationFailed) {
			try bob.unprotect(packet)
		}

		// A packet that fails authentication must not poison the stream for the real one.
		var (alice2, _) = try pipelines()
		let good = try alice2.protect(Data([1, 2, 3]))
		#expect(try bob.unprotect(good).payload == Data([1, 2, 3]))
	}

	@Test("rejects replays")
	func rejectsReplays() throws {
		var (alice, bob) = try pipelines()
		let packet = try alice.protect(Data([9]))

		_ = try bob.unprotect(packet)

		#expect(throws: CallAudioPipeline.ReceiveError.replayed) {
			try bob.unprotect(packet)
		}
	}

	@Test("accepts reordered packets inside the window")
	func acceptsReorderedPackets() throws {
		var (alice, bob) = try pipelines()
		let first = try alice.protect(Data([1]))
		let second = try alice.protect(Data([2]))
		let third = try alice.protect(Data([3]))

		#expect(try bob.unprotect(third).payload == Data([3]))
		#expect(try bob.unprotect(first).payload == Data([1]))
		#expect(try bob.unprotect(second).payload == Data([2]))
	}

	@Test("rejects short or truncated packets")
	func rejectsShortPackets() throws {
		var (_, bob) = try pipelines()

		#expect(throws: CallAudioPipeline.ReceiveError.malformed) {
			try bob.unprotect(Data(count: 10))
		}
		let headerOnly = CallRTPHeader(sequenceNumber: 1, timestamp: 0, ssrc: 1).encoded() + Data(count: 4)
		#expect(throws: CallAudioPipeline.ReceiveError.malformed) {
			try bob.unprotect(headerOnly)
		}
	}

	@Test("keeps decrypting across a sequence number wrap")
	func survivesSequenceWrap() throws {
		var (alice, bob) = try pipelines()
		for index in 0..<70_000 {
			let packet = try alice.protect(Data([UInt8(truncatingIfNeeded: index)]))
			let received = try bob.unprotect(packet)
			#expect(received.payload == Data([UInt8(truncatingIfNeeded: index)]))
		}
	}

	@Test("tracks ROC estimates around the wrap")
	func estimatesROC() {
		var stream = CallAudioPipeline.ReceiveStream()
		#expect(stream.estimateROC(for: 100) == 0)
		_ = stream.accept(sequence: 65_000, roc: 0)
		#expect(stream.estimateROC(for: 10) == 1)
		#expect(stream.estimateROC(for: 64_990) == 0)
	}
}

extension Data {
	var hex: String {
		map { String(format: "%02x", $0) }.joined()
	}
}
