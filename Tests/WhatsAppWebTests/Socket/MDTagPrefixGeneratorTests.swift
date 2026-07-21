import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("MD tag prefix generator")
struct MDTagPrefixGeneratorTests {
	@Test("generates Baileys MD tag prefix from two big-endian words")
	func generatesBaileysMDTagPrefixFromTwoBigEndianWords() throws {
		let generator = MDTagPrefixGenerator { count in
			#expect(count == 4)
			return Data([0x12, 0x34, 0xab, 0xcd])
		}

		#expect(try generator.generate() == "4660.43981-")
	}

	@Test("keeps zero words in the prefix")
	func keepsZeroWordsInThePrefix() throws {
		let generator = MDTagPrefixGenerator { _ in Data([0x00, 0x00, 0x00, 0x07]) }

		#expect(try generator.generate() == "0.7-")
	}

	@Test("rejects invalid random byte counts")
	func rejectsInvalidRandomByteCounts() {
		let generator = MDTagPrefixGenerator { _ in Data([0x01, 0x02, 0x03]) }

		#expect(throws: MDTagPrefixGeneratorError.invalidRandomByteCount) {
			try generator.generate()
		}
	}
}
