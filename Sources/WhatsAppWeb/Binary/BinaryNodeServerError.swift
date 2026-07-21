import Foundation

public struct BinaryNodeServerError: Error, Equatable, Sendable {
	public let message: String
	public let code: Int?
	public let node: BinaryNode

	public init(message: String, code: Int?, node: BinaryNode) {
		self.message = message
		self.code = code
		self.node = node
	}
}

public extension BinaryNode {
	func assertServerErrorFree() throws {
		if let error = firstChild(named: "error") {
			throw BinaryNodeServerError(
				message: error.attrs["text"] ?? "Unknown error",
				code: error.attrs["code"].flatMap(Int.init),
				node: error
			)
		}

		if attrs["type"] == "error" {
			throw BinaryNodeServerError(
				message: attrs["text"] ?? "Unknown error",
				code: attrs["code"].flatMap(Int.init),
				node: self
			)
		}
	}
}
