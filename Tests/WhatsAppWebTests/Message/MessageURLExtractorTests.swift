import Testing
@testable import WhatsAppWeb

@Suite("Message URL extractor")
struct MessageURLExtractorTests {
	@Test("returns the first https URL")
	func returnsFirstHTTPSURL() {
		let text = "Read https://example.com/a?b=1 and https://second.example/path"

		#expect(MessageURLExtractor.extractURL(from: text) == "https://example.com/a?b=1")
	}

	@Test("supports domains ports and paths")
	func supportsDomainsPortsAndPaths() {
		let text = "Open https://sub.example.co.mz:8443/products/item-1?ref=wa#details"

		#expect(MessageURLExtractor.extractURL(from: text) == "https://sub.example.co.mz:8443/products/item-1?ref=wa#details")
	}

	@Test("ignores non https and credential URLs")
	func ignoresNonHTTPSAndCredentialURLs() {
		#expect(MessageURLExtractor.extractURL(from: "http://example.com") == nil)
		#expect(MessageURLExtractor.extractURL(from: "https://user:pass@example.com/path") == nil)
	}

	@Test("stops bare domain URLs before punctuation")
	func stopsBareDomainURLsBeforePunctuation() {
		#expect(MessageURLExtractor.extractURL(from: "Visit https://example.com, now") == "https://example.com")
	}
}
