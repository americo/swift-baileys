import Testing
@testable import WhatsAppWeb

@Suite("Media upload token encoder")
struct MediaUploadTokenEncoderTests {
	@Test("converts base64 hashes to Baileys upload tokens")
	func convertsBase64HashesToBaileysUploadTokens() {
		#expect(MediaUploadTokenEncoder.encodeBase64ForUpload("AB+//ZA==") == "AB-__ZA")
		#expect(MediaUploadTokenEncoder.encodeBase64ForUpload("already_URL-safe") == "already_URL-safe")
		#expect(MediaUploadTokenEncoder.encodeBase64ForUpload("abc=") == "abc")
	}
}
