import Foundation
import Testing
@testable import WhatsAppWeb

/// Known-answer vectors taken from the reverse-engineered reference implementation's `kats.json`.
@Suite("Call media crypto")
struct CallMediaCryptoTests {
	private let callKey = Data(hex: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
	private let selfLID = "111111111111111:0@lid"
	private let peerLID = "222222222222222:0@lid"
	private let ssrc: UInt32 = 305_419_896
	private let sequence: UInt16 = 7
	private let roc: UInt32 = 0
	private let payload = Data(hex: "102132435465768798a9bacb")
	private let samplePacket = Data(hex: "90780007000003c012345678deadbeef")

	@Test("derives peer keys")
	func derivesPeerKeys() throws {
		let keys = try CallMediaCrypto.deriveRTPKeys(callKey: callKey, participantID: peerLID)

		#expect(keys.cipherKey == Data(hex: "747055a9d18be0fcdc0e29d871309081"))
		#expect(keys.salt == Data(hex: "10fb8133eff7639cc0d06788f49c"))
		#expect(keys.authKey == Data(hex: "8eff4bb04971d92512b034ce0ebc466059bfc6ea"))
	}

	@Test("derives self keys")
	func derivesSelfKeys() throws {
		let keys = try CallMediaCrypto.deriveRTPKeys(callKey: callKey, participantID: selfLID)

		#expect(keys.cipherKey == Data(hex: "261bde5b556020e3e6da0f5e3132db57"))
		#expect(keys.salt == Data(hex: "44224a8c019b379c4bbf7dda284a"))
		#expect(keys.authKey == Data(hex: "56b2655b60a1c17c03dfe94950d5df233481ad41"))
	}

	@Test("builds the RTP IV")
	func buildsRTPIV() throws {
		let keys = try CallMediaCrypto.deriveRTPKeys(callKey: callKey, participantID: peerLID)
		let iv = CallMediaCrypto.rtpIV(salt: keys.salt, ssrc: ssrc, roc: roc, sequence: sequence)

		#expect(iv == Data(hex: "10fb8133fdc335e4c0d06788f49b0000"))
	}

	@Test("encrypts and decrypts payloads")
	func encryptsAndDecryptsPayloads() throws {
		let keys = try CallMediaCrypto.deriveRTPKeys(callKey: callKey, participantID: peerLID)
		let cipher = try CallMediaCrypto.cryptPayload(payload, keys: keys, ssrc: ssrc, roc: roc, sequence: sequence)

		#expect(cipher == Data(hex: "17b30591a2650ed7bbae9c5a"))
		let plain = try CallMediaCrypto.cryptPayload(cipher, keys: keys, ssrc: ssrc, roc: roc, sequence: sequence)
		#expect(plain == payload)
	}

	@Test("computes and verifies the WARP tag")
	func computesAndVerifiesWarpTag() throws {
		let keys = try CallMediaCrypto.deriveRTPKeys(callKey: callKey, participantID: peerLID)
		let tag = CallMediaCrypto.warpTag(authKey: keys.authKey, packetWithoutTag: samplePacket, roc: roc)

		#expect(tag == Data(hex: "53fada83"))
		#expect(CallMediaCrypto.verifyWarpTag(
			authKey: keys.authKey,
			packetWithoutTag: samplePacket,
			roc: roc,
			receivedTag: tag
		))
		#expect(!CallMediaCrypto.verifyWarpTag(
			authKey: keys.authKey,
			packetWithoutTag: samplePacket,
			roc: roc,
			receivedTag: Data(hex: "53fada84")
		))
		#expect(!CallMediaCrypto.verifyWarpTag(
			authKey: keys.authKey,
			packetWithoutTag: samplePacket,
			roc: roc,
			receivedTag: Data()
		))
	}

	@Test("rejects short call keys")
	func rejectsShortCallKeys() {
		#expect(throws: CallMediaCryptoError.callKeyTooShort) {
			try CallMediaCrypto.deriveRTPKeys(callKey: Data(count: 16), participantID: peerLID)
		}
	}

	@Test("formats participant ids")
	func formatsParticipantIDs() {
		#expect(CallMediaCrypto.formatParticipantID("123@lid") == "123:0@lid")
		#expect(CallMediaCrypto.formatParticipantID("123:4@lid") == "123:4@lid")
		#expect(CallMediaCrypto.formatParticipantID("123:4@lid/res") == "123:4@lid")
		#expect(CallMediaCrypto.formatParticipantID("123@s.whatsapp.net") == "123@s.whatsapp.net")
	}
}

extension Data {
	init(hex: String) {
		var bytes = [UInt8]()
		var index = hex.startIndex
		while index < hex.endIndex {
			let next = hex.index(index, offsetBy: 2)
			bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
			index = next
		}
		self.init(bytes)
	}
}
