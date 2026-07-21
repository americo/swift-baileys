import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp browser description")
struct WhatsAppBrowserDescriptionTests {
	@Test("builds Baileys browser presets")
	func buildsBaileysBrowserPresets() {
		#expect(WhatsAppBrowserDescription.ubuntu("Chrome") == WhatsAppBrowserDescription(os: "Ubuntu", browser: "Chrome", version: "22.04.4"))
		#expect(WhatsAppBrowserDescription.macOS("Safari") == WhatsAppBrowserDescription(os: "Mac OS", browser: "Safari", version: "14.4.1"))
		#expect(WhatsAppBrowserDescription.baileys("Chrome") == WhatsAppBrowserDescription(os: "Baileys", browser: "Chrome", version: "6.5.0"))
		#expect(WhatsAppBrowserDescription.windows("Edge") == WhatsAppBrowserDescription(os: "Windows", browser: "Edge", version: "10.0.22631"))
	}

	@Test("maps companion web client type like Baileys")
	func mapsCompanionWebClientTypeLikeBaileys() {
		#expect(WhatsAppBrowserPlatform.companionPlatformID(for: .macOS("Desktop")) == "7")
		#expect(WhatsAppBrowserPlatform.companionPlatformID(for: .windows("Desktop")) == "8")
		#expect(WhatsAppBrowserPlatform.companionPlatformID(for: .macOS("Chrome")) == "1")
		#expect(WhatsAppBrowserPlatform.companionPlatformID(for: .macOS("Safari")) == "6")
		#expect(WhatsAppBrowserPlatform.companionPlatformID(for: .macOS("Unknown")) == "9")
	}

	@Test("maps protobuf platform ids with Chrome fallback")
	func mapsProtobufPlatformIDsWithChromeFallback() {
		#expect(WhatsAppBrowserPlatform.platformID(for: "Chrome") == "1")
		#expect(WhatsAppBrowserPlatform.platformID(for: "Firefox") == "2")
		#expect(WhatsAppBrowserPlatform.platformID(for: "Desktop") == "7")
		#expect(WhatsAppBrowserPlatform.platformID(for: "UWP") == "21")
		#expect(WhatsAppBrowserPlatform.platformID(for: "Unknown") == "1")
	}

	@Test("builds pairing QR data from browser description")
	func buildsPairingQRDataFromBrowserDescription() {
		let credentials = AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data(repeating: 1, count: 32), publicKey: Data([0x01, 0x02])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data(), publicKey: Data()),
			signedIdentityKey: AuthenticationKeyPair(privateKey: Data(repeating: 3, count: 32), publicKey: Data([0x03, 0x04])),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(privateKey: Data(), publicKey: Data()),
				signature: Data(),
				keyID: 1
			),
			registrationID: 1,
			advSecretKey: "adv-secret",
			nextPreKeyID: 1,
			firstUnuploadedPreKeyID: 1,
			accountSyncCounter: 0,
			registered: false
		)

		let qr = PairingQRCode.build(ref: "ref-1", credentials: credentials, browser: .macOS("Safari"))

		#expect(qr == "https://wa.me/settings/linked_devices#ref-1,AQI=,AwQ=,adv-secret,6")
	}
}
