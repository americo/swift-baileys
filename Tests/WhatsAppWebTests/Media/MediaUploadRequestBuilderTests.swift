import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Media upload request builder")
struct MediaUploadRequestBuilderTests {
	@Test("builds image upload URLs matching Baileys")
	func buildsImageUploadURLsMatchingBaileys() throws {
		let request = try MediaUploadRequestBuilder.build(
			hostname: "mmg.whatsapp.net",
			authToken: "auth/token+value=",
			fileEncSha256Base64: "AB+//ZA==",
			mediaType: .image
		)

		#expect(request.url.absoluteString == "https://mmg.whatsapp.net/mms/image/AB-__ZA?auth=auth%2Ftoken%2Bvalue%3D&token=AB-__ZA")
		#expect(request.headers == [
			"Content-Type": "application/octet-stream",
			"Origin": "https://web.whatsapp.com"
		])
	}

	@Test("rejects empty upload URL inputs")
	func rejectsEmptyUploadURLInputs() throws {
		#expect(throws: MediaUploadRequestBuilderError.emptyHostname) {
			try MediaUploadRequestBuilder.build(
				hostname: "",
				authToken: "auth-token",
				fileEncSha256Base64: "ABCD",
				mediaType: .image
			)
		}
		#expect(throws: MediaUploadRequestBuilderError.emptyAuthToken) {
			try MediaUploadRequestBuilder.build(
				hostname: "mmg.whatsapp.net",
				authToken: "",
				fileEncSha256Base64: "ABCD",
				mediaType: .image
			)
		}
		#expect(throws: MediaUploadRequestBuilderError.emptyFileEncSHA256) {
			try MediaUploadRequestBuilder.build(
				hostname: "mmg.whatsapp.net",
				authToken: "auth-token",
				fileEncSha256Base64: "",
				mediaType: .image
			)
		}
	}
}
