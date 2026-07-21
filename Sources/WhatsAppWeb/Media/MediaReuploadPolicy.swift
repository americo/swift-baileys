import Foundation

public enum MediaReuploadPolicy {
	public static func requiresReupload(forStatusCode statusCode: Int) -> Bool {
		statusCode == 404 || statusCode == 410
	}

	public static func statusCode(from error: any Error) -> Int? {
		guard case let URLSessionMediaDownloadTransportError.httpStatus(statusCode, _) = error else {
			return nil
		}

		return statusCode
	}
}
