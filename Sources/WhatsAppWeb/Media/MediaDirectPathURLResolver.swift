import Foundation

public enum MediaDirectPathURLResolver {
	public static let defaultHost = "mmg.whatsapp.net"

	public static func url(from directPath: String, host: String = defaultHost) -> URL? {
		URL(string: "https://\(host)\(directPath)")
	}
}
