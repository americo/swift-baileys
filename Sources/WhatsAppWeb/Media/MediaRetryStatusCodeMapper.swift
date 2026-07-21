import Foundation

public enum MediaRetryStatusCodeMapper {
	public static func statusCode(for resultCode: Int) -> Int? {
		switch Proto_MediaRetryNotification.ResultType(rawValue: resultCode) {
		case .success:
			200
		case .decryptionError:
			412
		case .notFound:
			404
		case .generalError:
			418
		case .UNRECOGNIZED, nil:
			nil
		}
	}
}
