import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Call Opus codec")
struct CallOpusCodecTests {
	private func tone(frequency: Double = 440, frames: Int = 960, offset: Int = 0) -> [Int16] {
		(0..<frames).map { index in
			let t = Double(index + offset) / CallAudioFormat.sampleRate
			return Int16(8_000 * sin(2 * .pi * frequency * t))
		}
	}

	private func energy(_ samples: [Int16]) -> Double {
		samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(max(samples.count, 1))
	}

	@Test("encodes a 60 ms frame into a small Opus packet")
	func encodesFrame() throws {
		let encoder = try CallOpusEncoder()
		let packet = try encoder.encode(tone())

		#expect(!packet.isEmpty)
		#expect(packet.count < 400)
		// The Opus TOC byte's frame-size code for 60 ms packets: configurations 3, 7, 11, 15, ...
		#expect(packet[packet.startIndex] & 0b0000_0011 <= 3)
	}

	@Test("roundtrips audio with its energy preserved")
	func roundtripsAudio() throws {
		let encoder = try CallOpusEncoder()
		let decoder = try CallOpusDecoder()
		var decoded = [Int16]()
		for frame in 0..<8 {
			let packet = try encoder.encode(tone(offset: frame * 960))
			decoded += try decoder.decode(packet)
		}

		#expect(decoded.count >= 960 * 6)
		let steady = Array(decoded.suffix(960 * 4))
		let original = tone(frames: 960 * 4)
		let ratio = energy(steady) / energy(original)
		#expect(ratio > 0.3 && ratio < 3.0)
	}

	@Test("silence stays quiet")
	func silenceStaysQuiet() throws {
		let encoder = try CallOpusEncoder()
		let decoder = try CallOpusDecoder()
		var decoded = [Int16]()
		for _ in 0..<4 {
			decoded += try decoder.decode(encoder.encode([Int16](repeating: 0, count: 960)))
		}

		#expect(energy(decoded) < 100)
	}

	@Test("rejects frames of the wrong size")
	func rejectsWrongFrameSize() throws {
		let encoder = try CallOpusEncoder()

		#expect(throws: CallOpusError.wrongFrameSize(100)) {
			try encoder.encode([Int16](repeating: 0, count: 100))
		}
	}

	@Test("rejects empty and oversized packets")
	func rejectsBadPackets() throws {
		let decoder = try CallOpusDecoder()

		#expect(throws: CallOpusError.self) { try decoder.decode(Data()) }
		#expect(throws: CallOpusError.self) { try decoder.decode(Data(count: 5_000)) }
	}
}

@Suite("Call relay selection")
struct CallRelaySelectionTests {
	private func endpoint(
		_ name: String,
		id: UInt32,
		fna: Bool = false,
		token: Int = 0,
		auth: Int = 0,
		port: UInt16 = 3478
	) -> CallRelayEndpoint {
		CallRelayEndpoint(
			relayID: id,
			relayName: name,
			tokenID: token,
			authTokenID: auth,
			isFNA: fna,
			ipv4Bytes: nil,
			addresses: [CallRelayAddress(protocolID: 0, ipv4: "1.2.3.\(id)", ipv6: nil, port: port)],
			clientToRelayRTTMs: nil
		)
	}

	private func relay(_ endpoints: [CallRelayEndpoint], tokens: [Data] = [Data([1]), Data([2])]) -> CallRelayData {
		CallRelayData(relayTokens: tokens, authTokens: [], endpoints: endpoints)
	}

	@Test("prefers the web client port")
	func prefersWebClientPort() {
		let data = relay([endpoint("a", id: 1, auth: 1), endpoint("b", id: 2, port: 3480)])

		#expect(data.mediaEndpoint()?.relayName == "b")
	}

	@Test("falls back to an outbound candidate, then a non-FNA one")
	func fallsBackToOutboundCandidate() {
		let outbound = relay([endpoint("fna", id: 1, fna: true), endpoint("plain", id: 2), endpoint("auth", id: 3, auth: 1)])
		#expect(outbound.mediaEndpoint()?.relayName == "auth")

		let plain = relay([endpoint("fna", id: 1, fna: true), endpoint("plain", id: 2)])
		#expect(plain.mediaEndpoint()?.relayName == "plain")
	}

	@Test("skips endpoints whose token was never sent")
	func skipsEndpointsWithoutToken() {
		let data = relay([endpoint("notoken", id: 1, token: 5, port: 3480), endpoint("ok", id: 2)])

		#expect(data.mediaEndpoint()?.relayName == "ok")
	}

	@Test("returns nil without endpoints")
	func returnsNilWithoutEndpoints() {
		#expect(relay([]).mediaEndpoint() == nil)
	}
}
