import Foundation

public enum MediaUploadTokenEncoder {
	public static func encodeBase64ForUpload(_ base64: String) -> String {
		base64
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: #"=+$"#, with: "", options: .regularExpression)
	}
}
