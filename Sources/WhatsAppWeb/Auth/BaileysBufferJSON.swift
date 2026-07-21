import Foundation

public enum BaileysBufferJSON {
	public static func object(from data: Data) -> [String: Any] {
		[
			"type": "Buffer",
			"data": data.base64EncodedString()
		]
	}

	public static func data(from object: Any) throws -> Data {
		if let string = object as? String, let data = Data(base64Encoded: string) {
			return data
		}

		guard let transformed = transformBufferJSON(object) as? String,
			  let data = Data(base64Encoded: transformed) else {
			throw BaileysBufferJSONError.invalidBufferObject
		}

		return data
	}

	public static func decode<T: Decodable>(
		_ type: T.Type,
		from data: Data,
		decoder: JSONDecoder = JSONDecoder()
	) throws -> T {
		let object = try JSONSerialization.jsonObject(with: data)
		let transformed = transformBufferJSON(object)
		let transformedData = try JSONSerialization.data(withJSONObject: transformed)
		return try decoder.decode(type, from: transformedData)
	}

	private static func transformBufferJSON(_ object: Any) -> Any {
		if let dictionary = object as? [String: Any] {
			if let data = dictionary["data"] as? String,
			   dictionary["type"] as? String == "Buffer" {
				return data
			}

			if let numericData = dataFromNumericObject(dictionary) {
				return numericData.base64EncodedString()
			}

			return dictionary.mapValues { transformBufferJSON($0) }
		}

		if let array = object as? [Any] {
			return array.map { transformBufferJSON($0) }
		}

		return object
	}

	private static func dataFromNumericObject(_ dictionary: [String: Any]) -> Data? {
		guard !dictionary.isEmpty else {
			return nil
		}

		let pairs = dictionary.compactMap { key, value -> (Int, UInt8)? in
			guard let index = Int(key),
				  let number = value as? Int,
				  (0...255).contains(number) else {
				return nil
			}

			return (index, UInt8(number))
		}

		guard pairs.count == dictionary.count else {
			return nil
		}

		return Data(pairs.sorted { $0.0 < $1.0 }.map(\.1))
	}
}

public enum BaileysBufferJSONError: Error, Equatable, Sendable {
	case invalidBufferObject
}
