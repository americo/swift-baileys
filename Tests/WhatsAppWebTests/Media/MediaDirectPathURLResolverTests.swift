import Testing
@testable import WhatsAppWeb

@Suite("Media direct path URL resolver")
struct MediaDirectPathURLResolverTests {
	@Test("builds direct path URL with default media host")
	func buildsDirectPathURLWithDefaultMediaHost() throws {
		let url = try #require(MediaDirectPathURLResolver.url(
			from: "/v/t62.7118-24/media.enc?ccb=11-4&oh=01"
		))

		#expect(url.absoluteString == "https://mmg.whatsapp.net/v/t62.7118-24/media.enc?ccb=11-4&oh=01")
	}

	@Test("builds direct path URL with custom media host")
	func buildsDirectPathURLWithCustomMediaHost() throws {
		let url = try #require(MediaDirectPathURLResolver.url(
			from: "/v/t62.7118-24/media.enc",
			host: "mmg-fna.whatsapp.net"
		))

		#expect(url.absoluteString == "https://mmg-fna.whatsapp.net/v/t62.7118-24/media.enc")
	}
}
