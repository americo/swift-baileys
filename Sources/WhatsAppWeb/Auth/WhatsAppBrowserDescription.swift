import Foundation

public struct WhatsAppBrowserDescription: Equatable, Sendable {
	public let os: String
	public let browser: String
	public let version: String

	public init(os: String, browser: String, version: String) {
		self.os = os
		self.browser = browser
		self.version = version
	}

	public static func ubuntu(_ browser: String) -> WhatsAppBrowserDescription {
		WhatsAppBrowserDescription(os: "Ubuntu", browser: browser, version: "22.04.4")
	}

	public static func macOS(_ browser: String) -> WhatsAppBrowserDescription {
		WhatsAppBrowserDescription(os: "Mac OS", browser: browser, version: "14.4.1")
	}

	public static func baileys(_ browser: String) -> WhatsAppBrowserDescription {
		WhatsAppBrowserDescription(os: "Baileys", browser: browser, version: "6.5.0")
	}

	public static func windows(_ browser: String) -> WhatsAppBrowserDescription {
		WhatsAppBrowserDescription(os: "Windows", browser: browser, version: "10.0.22631")
	}

	public static func appropriate(_ browser: String) -> WhatsAppBrowserDescription {
		#if os(macOS)
			let osName = "Mac OS"
		#elseif os(Windows)
			let osName = "Windows"
		#elseif os(Android)
			let osName = "Android"
		#else
			let osName = "Ubuntu"
		#endif
		return WhatsAppBrowserDescription(
			os: osName,
			browser: browser,
			version: ProcessInfo.processInfo.operatingSystemVersionString
		)
	}
}

public enum CompanionWebClientType: Int, Sendable {
	case unknown = 0
	case chrome = 1
	case edge = 2
	case firefox = 3
	case ie = 4
	case opera = 5
	case safari = 6
	case electron = 7
	case uwp = 8
	case otherWebClient = 9
}

public enum WhatsAppBrowserPlatform {
	public static func companionWebClientType(
		for browser: WhatsAppBrowserDescription
	) -> CompanionWebClientType {
		if browser.browser == "Desktop" {
			return browser.os == "Windows" ? .uwp : .electron
		}

		switch browser.browser {
		case "Chrome":
			return .chrome
		case "Edge":
			return .edge
		case "Firefox":
			return .firefox
		case "IE":
			return .ie
		case "Opera":
			return .opera
		case "Safari":
			return .safari
		default:
			return .otherWebClient
		}
	}

	public static func companionPlatformID(for browser: WhatsAppBrowserDescription) -> String {
		String(companionWebClientType(for: browser).rawValue)
	}

	public static func platformID(for browserName: String) -> String {
		switch browserName.uppercased() {
		case "CHROME":
			return String(Proto_DeviceProps.PlatformType.chrome.rawValue)
		case "FIREFOX":
			return String(Proto_DeviceProps.PlatformType.firefox.rawValue)
		case "IE":
			return String(Proto_DeviceProps.PlatformType.ie.rawValue)
		case "OPERA":
			return String(Proto_DeviceProps.PlatformType.opera.rawValue)
		case "SAFARI":
			return String(Proto_DeviceProps.PlatformType.safari.rawValue)
		case "EDGE":
			return String(Proto_DeviceProps.PlatformType.edge.rawValue)
		case "DESKTOP":
			return String(Proto_DeviceProps.PlatformType.desktop.rawValue)
		case "UWP":
			return String(Proto_DeviceProps.PlatformType.uwp.rawValue)
		default:
			return String(Proto_DeviceProps.PlatformType.chrome.rawValue)
		}
	}
}
