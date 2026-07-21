import Testing
@testable import WhatsAppWeb

@Suite("Media retry status code mapper")
struct MediaRetryStatusCodeMapperTests {
	@Test("maps media retry result codes to Baileys status codes")
	func mapsMediaRetryResultCodesToBaileysStatusCodes() {
		#expect(MediaRetryStatusCodeMapper.statusCode(for: 1) == 200)
		#expect(MediaRetryStatusCodeMapper.statusCode(for: 3) == 412)
		#expect(MediaRetryStatusCodeMapper.statusCode(for: 2) == 404)
		#expect(MediaRetryStatusCodeMapper.statusCode(for: 0) == 418)
		#expect(MediaRetryStatusCodeMapper.statusCode(for: 999) == nil)
	}
}
