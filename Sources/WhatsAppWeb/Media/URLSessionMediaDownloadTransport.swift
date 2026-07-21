import Foundation

public struct URLSessionMediaDownloadTransport: MediaDownloading {
	private let session: URLSession

	public init(session: URLSession = .shared) {
		self.session = session
	}

	public func download(from url: URL) async throws -> Data {
		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		let (data, response) = try await session.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse else {
			throw URLSessionMediaDownloadTransportError.nonHTTPResponse
		}
		guard 200..<300 ~= httpResponse.statusCode else {
			throw URLSessionMediaDownloadTransportError.httpStatus(httpResponse.statusCode, data)
		}
		return data
	}
}

public enum URLSessionMediaDownloadTransportError: Error, Equatable, Sendable {
	case nonHTTPResponse
	case httpStatus(Int, Data)
}
