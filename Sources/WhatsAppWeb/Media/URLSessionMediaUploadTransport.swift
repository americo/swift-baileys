import Foundation

public struct URLSessionMediaUploadTransport: MediaUploading {
	private let session: URLSession

	public init(session: URLSession = .shared) {
		self.session = session
	}

	public func upload(data: Data, request: MediaUploadRequest) async throws -> MediaUploadTransportResult? {
		var urlRequest = URLRequest(url: request.url)
		urlRequest.httpMethod = "POST"
		urlRequest.httpBody = data
		for (field, value) in request.headers {
			urlRequest.setValue(value, forHTTPHeaderField: field)
		}

		let (responseData, response) = try await session.data(for: urlRequest)
		guard let httpResponse = response as? HTTPURLResponse else {
			throw URLSessionMediaUploadTransportError.nonHTTPResponse
		}
		guard 200..<300 ~= httpResponse.statusCode else {
			throw URLSessionMediaUploadTransportError.httpStatus(httpResponse.statusCode, responseData)
		}
		guard let response = try? JSONDecoder().decode(MediaUploadResponse.self, from: responseData),
			  let mediaURL = response.url,
			  let directPath = response.directPath else {
			return nil
		}

		return MediaUploadTransportResult(
			mediaURL: mediaURL,
			directPath: directPath,
			metaHMAC: response.metaHMAC,
			timestamp: response.timestamp,
			fileID: response.fileID
		)
	}
}

public enum URLSessionMediaUploadTransportError: Error, Equatable, Sendable {
	case nonHTTPResponse
	case httpStatus(Int, Data)
}

private struct MediaUploadResponse: Decodable {
	let url: String?
	let directPath: String?
	let metaHMAC: String?
	let timestamp: Int?
	let fileID: Int?

	enum CodingKeys: String, CodingKey {
		case url
		case directPath = "direct_path"
		case metaHMAC = "meta_hmac"
		case timestamp = "ts"
		case fileID = "fbid"
	}
}
