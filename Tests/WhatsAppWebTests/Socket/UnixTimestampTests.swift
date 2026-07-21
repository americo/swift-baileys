import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Unix timestamp")
struct UnixTimestampTests {
	@Test("returns whole Unix seconds")
	func returnsWholeUnixSeconds() {
		#expect(UnixTimestamp.seconds(from: Date(timeIntervalSince1970: 1_700_000_000.999)) == 1_700_000_000)
	}

	@Test("floors negative fractional timestamps like JavaScript")
	func floorsNegativeFractionalTimestampsLikeJavaScript() {
		#expect(UnixTimestamp.seconds(from: Date(timeIntervalSince1970: -0.001)) == -1)
	}
}
