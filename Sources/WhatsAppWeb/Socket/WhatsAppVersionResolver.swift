import Foundation

public struct WhatsAppVersion: Equatable, Sendable {
	public let primary: Int
	public let secondary: Int
	public let tertiary: Int

	public var array: [Int] {
		[primary, secondary, tertiary]
	}

	public init(_ primary: Int, _ secondary: Int, _ tertiary: Int) {
		self.primary = primary
		self.secondary = secondary
		self.tertiary = tertiary
	}
}

public struct LatestWhatsAppVersionResult: Equatable, Sendable {
	public let version: WhatsAppVersion
	public let isLatest: Bool
	public let errorDescription: String?

	public init(version: WhatsAppVersion, isLatest: Bool, errorDescription: String? = nil) {
		self.version = version
		self.isLatest = isLatest
		self.errorDescription = errorDescription
	}
}

public enum WhatsAppVersionResolver {
	public static let bundledBaileysVersion = WhatsAppVersion(2, 3000, 1_035_194_821)

	public static func fetchLatestBaileysVersion(
		session: URLSession = .shared,
		url: URL = URL(string: "https://raw.githubusercontent.com/WhiskeySockets/Baileys/master/src/Defaults/index.ts")!
	) async -> LatestWhatsAppVersionResult {
		do {
			let text = try await fetchText(from: url, session: session)
			guard let version = parseBaileysVersion(from: text) else {
				return fallback("Could not parse version from Defaults/index.ts")
			}

			return LatestWhatsAppVersionResult(version: version, isLatest: true)
		} catch {
			return fallback(String(describing: error))
		}
	}

	public static func fetchLatestWaWebVersion(
		session: URLSession = .shared,
		url: URL = URL(string: "https://web.whatsapp.com/sw.js")!
	) async -> LatestWhatsAppVersionResult {
		do {
			let text = try await fetchText(from: url, session: session, headers: [
				"sec-fetch-site": "none",
				"user-agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
			])
			guard let revision = parseClientRevision(from: text) else {
				return fallback("Could not find client revision in the fetched content")
			}

			return LatestWhatsAppVersionResult(version: WhatsAppVersion(2, 3000, revision), isLatest: true)
		} catch {
			return fallback(String(describing: error))
		}
	}

	static func parseBaileysVersion(from text: String) -> WhatsAppVersion? {
		guard let match = text.firstMatch(of: /const version = \[(\d+),\s*(\d+),\s*(\d+)\]/),
			  let primary = Int(match.1),
			  let secondary = Int(match.2),
			  let tertiary = Int(match.3) else {
			return nil
		}

		return WhatsAppVersion(primary, secondary, tertiary)
	}

	static func parseClientRevision(from text: String) -> Int? {
		guard let match = text.firstMatch(of: /\\?"client_revision\\?":\s*(\d+)/) else {
			return nil
		}

		return Int(match.1)
	}

	private static func fetchText(
		from url: URL,
		session: URLSession,
		headers: [String: String] = [:]
	) async throws -> String {
		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		for (key, value) in headers {
			request.setValue(value, forHTTPHeaderField: key)
		}

		let (data, response) = try await session.data(for: request)
		if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
			throw WhatsAppVersionResolverError.httpStatus(http.statusCode)
		}

		return String(decoding: data, as: UTF8.self)
	}

	private static func fallback(_ errorDescription: String) -> LatestWhatsAppVersionResult {
		LatestWhatsAppVersionResult(
			version: bundledBaileysVersion,
			isLatest: false,
			errorDescription: errorDescription
		)
	}
}

public enum WhatsAppVersionResolverError: Error, Equatable, Sendable {
	case httpStatus(Int)
}
