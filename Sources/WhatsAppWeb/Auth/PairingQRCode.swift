import Foundation

public enum PairingQRCode {
	public static func build(
		ref: String,
		credentials: AuthenticationCredentials,
		platformID: String = "7"
	) -> String {
		let noiseKey = credentials.noiseKey.publicKey.base64EncodedString()
		let identityKey = credentials.signedIdentityKey.publicKey.base64EncodedString()

		return "https://wa.me/settings/linked_devices#\(ref),\(noiseKey),\(identityKey),\(credentials.advSecretKey),\(platformID)"
	}

	public static func build(
		ref: String,
		credentials: AuthenticationCredentials,
		browser: WhatsAppBrowserDescription
	) -> String {
		build(
			ref: ref,
			credentials: credentials,
			platformID: WhatsAppBrowserPlatform.companionPlatformID(for: browser)
		)
	}
}
