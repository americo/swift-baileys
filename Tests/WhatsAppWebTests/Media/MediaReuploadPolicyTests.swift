import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Media reupload policy")
struct MediaReuploadPolicyTests {
	@Test("requires reupload for Baileys media expiry statuses")
	func requiresReuploadForBaileysMediaExpiryStatuses() {
		#expect(MediaReuploadPolicy.requiresReupload(forStatusCode: 404))
		#expect(MediaReuploadPolicy.requiresReupload(forStatusCode: 410))
		#expect(!MediaReuploadPolicy.requiresReupload(forStatusCode: 403))
		#expect(!MediaReuploadPolicy.requiresReupload(forStatusCode: 500))
	}

	@Test("extracts status from URLSession download transport errors")
	func extractsStatusFromURLSessionDownloadTransportErrors() {
		let error = URLSessionMediaDownloadTransportError.httpStatus(410, Data("expired".utf8))

		#expect(MediaReuploadPolicy.statusCode(from: error) == 410)
	}
}
