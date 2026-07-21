import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Byte Crockford encoder")
struct ByteCrockfordEncoderTests {
	@Test("encodes empty data as an empty string")
	func encodesEmptyDataAsEmptyString() {
		#expect(ByteCrockfordEncoder.encode(Data()) == "")
	}

	@Test("encodes single byte values with Baileys alphabet")
	func encodesSingleByteValuesWithBaileysAlphabet() {
		#expect(ByteCrockfordEncoder.encode(Data([0x00])) == "11")
		#expect(ByteCrockfordEncoder.encode(Data([0xff])) == "ZW")
	}

	@Test("encodes pairing code bytes with Baileys fixture")
	func encodesPairingCodeBytesWithBaileysFixture() {
		#expect(ByteCrockfordEncoder.encode(Data([0, 1, 2, 3, 4])) == "111H51R5")
	}

	@Test("encodes longer byte buffers without retaining consumed bits")
	func encodesLongerByteBuffersWithoutRetainingConsumedBits() {
		#expect(ByteCrockfordEncoder.encode(Data(0...15)) == "111H51R51M41F31A296HR49F2W")
	}
}
