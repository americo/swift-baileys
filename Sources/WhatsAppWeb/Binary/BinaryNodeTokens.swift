import Foundation

struct BinaryNodeToken: Sendable {
	let dictionary: UInt8
	let index: UInt8
}

enum BinaryNodeTokenError: Error {
	case missingResource
	case invalidDoubleToken(dictionary: Int, index: Int)
}

struct BinaryNodeTokens: Sendable {
	static let shared = try! BinaryNodeTokens.load()

	let singleByte: [String]
	let singleByteByString: [String: UInt8]
	let doubleByte: [[String]]
	let doubleByteByString: [String: BinaryNodeToken]

	func doubleByteToken(dictionary: Int, index: Int) throws -> String {
		guard doubleByte.indices.contains(dictionary),
			  doubleByte[dictionary].indices.contains(index) else {
			throw BinaryNodeTokenError.invalidDoubleToken(dictionary: dictionary, index: index)
		}

		return doubleByte[dictionary][index]
	}

	private static func load() throws -> BinaryNodeTokens {
		guard let url = Bundle.module.url(forResource: "tokens", withExtension: "json") else {
			throw BinaryNodeTokenError.missingResource
		}

		let payload = try JSONDecoder().decode(TokenPayload.self, from: Data(contentsOf: url))
		var singleByteByString: [String: UInt8] = [:]
		for (index, token) in payload.singleByteTokens.enumerated() where !token.isEmpty {
			singleByteByString[token] = UInt8(index)
		}

		var doubleByteByString: [String: BinaryNodeToken] = [:]
		for (dictionaryIndex, dictionary) in payload.doubleByteTokens.enumerated() {
			for (tokenIndex, token) in dictionary.enumerated() {
				doubleByteByString[token] = BinaryNodeToken(dictionary: UInt8(dictionaryIndex), index: UInt8(tokenIndex))
			}
		}

		return BinaryNodeTokens(
			singleByte: payload.singleByteTokens,
			singleByteByString: singleByteByString,
			doubleByte: payload.doubleByteTokens,
			doubleByteByString: doubleByteByString
		)
	}
}

private struct TokenPayload: Decodable {
	let singleByteTokens: [String]
	let doubleByteTokens: [[String]]
}
