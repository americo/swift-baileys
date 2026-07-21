import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Big endian encoder")
struct BigEndianEncoderTests {
	@Test("encodes default four byte values like Baileys")
	func encodesDefaultFourByteValuesLikeBaileys() {
		#expect(BigEndianEncoder.encode(0x12345678) == Data([0x12, 0x34, 0x56, 0x78]))
	}

	@Test("encodes custom byte widths like Baileys")
	func encodesCustomByteWidthsLikeBaileys() {
		#expect(BigEndianEncoder.encode(0x123456, count: 3) == Data([0x12, 0x34, 0x56]))
		#expect(BigEndianEncoder.encode(7, count: 4) == Data([0x00, 0x00, 0x00, 0x07]))
	}

	@Test("keeps the least significant bytes when value exceeds width")
	func keepsLeastSignificantBytesWhenValueExceedsWidth() {
		#expect(BigEndianEncoder.encode(0x123456, count: 2) == Data([0x34, 0x56]))
	}
}
