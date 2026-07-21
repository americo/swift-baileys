import Foundation

public enum WMexQueryError: Error, Equatable, Sendable {
	case missingResult
	case invalidJSON
	case serverError(message: String, code: Int)
	case missingData(path: String)
	case invalidResponse(path: String)
}

struct WMexQueryResult: @unchecked Sendable {
	let object: [String: Any]

	subscript(key: String) -> Any? {
		object[key]
	}
}

extension WhatsAppClient {
	func executeWMexQuery(
		variables: [String: Any],
		queryID: String,
		dataPath: String,
		requestID: String?
	) async throws -> WMexQueryResult {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let payload = try JSONSerialization.data(withJSONObject: ["variables": variables], options: [])
		let result = try await query(
			BinaryNode(
				tag: "iq",
				attrs: [
					"id": id,
					"type": "get",
					"to": "@s.whatsapp.net",
					"xmlns": "w:mex"
				],
				content: .nodes([
					BinaryNode(tag: "query", attrs: ["query_id": queryID], content: .data(payload))
				])
			)
		)
		guard let resultData = result.firstChild(named: "result")?.contentData else {
			throw WMexQueryError.missingResult
		}

		guard let json = try JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
			throw WMexQueryError.invalidJSON
		}

		if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
			let message = errors.compactMap { $0["message"] as? String }.joined(separator: ", ")
			let extensions = errors[0]["extensions"] as? [String: Any]
			let code = extensions?["error_code"] as? Int ?? 400
			throw WMexQueryError.serverError(message: message.isEmpty ? "Unknown error" : message, code: code)
		}

		guard let data = json["data"] as? [String: Any], let response = data[dataPath] else {
			throw WMexQueryError.missingData(path: dataPath)
		}

		guard let object = response as? [String: Any] else {
			throw WMexQueryError.invalidResponse(path: dataPath)
		}

		return WMexQueryResult(object: object)
	}
}

private extension BinaryNode {
	var contentData: Data? {
		switch content {
		case let .data(data):
			data
		case let .string(string):
			Data(string.utf8)
		case .nodes, .none:
			nil
		}
	}
}
