import Testing
@testable import WhatsAppWeb

@Suite("String presence")
struct StringPresenceTests {
	@Test("treats nil and empty strings as null or empty")
	func treatsNilAndEmptyStringsAsNullOrEmpty() {
		#expect(StringPresence.isNullOrEmpty(nil))
		#expect(StringPresence.isNullOrEmpty(""))
	}

	@Test("treats non-empty strings as present")
	func treatsNonEmptyStringsAsPresent() {
		#expect(!StringPresence.isNullOrEmpty("0"))
		#expect(!StringPresence.isNullOrEmpty("offline"))
	}
}
