import Foundation
import Testing
@testable import WhatsAppWeb

/// Vectors from the reference implementation's `kats.json` (`stun` section).
@Suite("Call STUN")
struct CallSTUNTests {
	private let transactionID = Data(hex: "a0a1a2a3a4a5a6a7a8a9aaab")
	private let relayToken = Data(hex: "1020304050607080")
	private let integrityKey = Data(hex: "30313233343536373839616263646566")

	@Test("CRC-32 is IEEE")
	func crc32IsIEEE() {
		#expect(CallSTUN.crc32(Data("abc".utf8)) == 891_568_578)
		#expect(CallSTUN.crc32(Data("abc".utf8)) == 0x3524_41c2)
	}

	@Test("encodes the relay token attribute")
	func encodesRelayTokenAttribute() {
		#expect(CallSTUN.attribute(CallSTUN.attributeRelayToken, relayToken) == Data(hex: "400000081020304050607080"))
	}

	@Test("XOR-encodes the relay endpoint")
	func xorEncodesRelayEndpoint() {
		#expect(CallSTUN.xorRelayEndpoint(ipv4: "157.240.226.133", port: 3478) == Data(hex: "2c84bce246c7"))
		#expect(CallSTUN.xorRelayEndpoint(ipv4: "1.2.3", port: 1) == nil)
	}

	@Test("adds message integrity")
	func addsMessageIntegrity() {
		let packet = CallSTUN.encode(
			type: CallSTUN.allocateRequest,
			transactionID: transactionID,
			attributes: CallSTUN.attribute(CallSTUN.attributeRelayToken, relayToken),
			integrityKey: integrityKey
		)

		#expect(packet == Data(hex: "000300242112a442a0a1a2a3a4a5a6a7a8a9aaab4000000810203040506070800008001450c96f7efef837bbde7e1f534dae139816d3e015"))
	}

	@Test("adds fingerprint after integrity")
	func addsFingerprintAfterIntegrity() {
		let packet = CallSTUN.encode(
			type: CallSTUN.allocateRequest,
			transactionID: transactionID,
			attributes: CallSTUN.attribute(CallSTUN.attributeRelayToken, relayToken),
			integrityKey: integrityKey,
			includeFingerprint: true
		)

		#expect(packet == Data(hex: "0003002c2112a442a0a1a2a3a4a5a6a7a8a9aaab4000000810203040506070800008001450c96f7efef837bbde7e1f534dae139816d3e01580280004ade1f63c"))
	}

	@Test("builds the WhatsApp ping")
	func buildsWhatsAppPing() {
		let ping = CallSTUN.ping(transactionID: transactionID)

		#expect(ping == Data(hex: "080100002112a442a0a1a2a3a4a5a6a7a8a9aaab"))
		#expect(CallSTUN.isSTUN(ping))
		#expect(CallSTUN.transactionID(ping) == transactionID)
	}

	@Test("recognises pongs by transaction id")
	func recognisesPongs() {
		var pong = CallSTUN.ping(transactionID: transactionID)
		pong[pong.startIndex + 1] = 0x02

		#expect(CallSTUN.isPong(pong))
		#expect(CallSTUN.isPong(pong, transactionID: transactionID))
		#expect(!CallSTUN.isPong(pong, transactionID: Data(count: 12)))
	}

	@Test("truncated or misaligned messages drive no allocate decision")
	func truncatedMessagesDriveNoDecision() {
		let ok = CallSTUN.encode(type: CallSTUN.allocateSuccess, transactionID: Data(count: 12))
		#expect(CallSTUN.isAllocateOrBindingSuccess(ok))

		var truncated = ok
		truncated[truncated.startIndex + 3] = 0x40
		#expect(!CallSTUN.isAllocateOrBindingSuccess(truncated))

		var misaligned = ok
		misaligned[misaligned.startIndex + 3] = 0x03
		#expect(!CallSTUN.isComplete(misaligned))

		var error = CallSTUN.encode(type: CallSTUN.allocateError, transactionID: Data(count: 12))
		error[error.startIndex + 3] = 0x40
		#expect(!CallSTUN.isAllocateError(error))
	}

	@Test("reads the error code only from inside the declared body")
	func readsErrorCodeFromDeclaredBody() {
		let value = Data([0x00, 0x00, 0x04, 0x01])
		let body = CallSTUN.attribute(CallSTUN.attributeErrorCode, value)
		let packet = CallSTUN.encode(type: CallSTUN.allocateError, transactionID: Data(count: 12), attributes: body)
		#expect(CallSTUN.errorCode(packet) == 401)

		var outside = Data([0x01, 0x13, 0x00, 0x04])
		outside.append(contentsOf: [0x21, 0x12, 0xa4, 0x42])
		outside.append(Data(count: 12))
		outside.append(contentsOf: [0x00, 0x09, 0x00, 0x04])
		outside.append(contentsOf: [0x00, 0x00, 0x04, 0x01])
		#expect(CallSTUN.isAllocateError(outside))
		#expect(CallSTUN.errorCode(outside) == nil)
	}

	@Test("walks attributes with padding")
	func walksAttributesWithPadding() {
		let attributes = CallSTUN.attribute(0x4000, Data([1, 2, 3])) + CallSTUN.attribute(0x4001, Data([9]))
		let packet = CallSTUN.encode(type: CallSTUN.bindingRequest, transactionID: transactionID, attributes: attributes)

		#expect(CallSTUN.attributes(of: packet) == [
			CallSTUN.Attribute(type: 0x4000, value: Data([1, 2, 3])),
			CallSTUN.Attribute(type: 0x4001, value: Data([9]))
		])
	}
}
