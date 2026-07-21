import Foundation

public struct BinaryNode: Sendable {
	public typealias Attributes = BinaryNodeAttributes

	public enum Content: Equatable, Sendable {
		case nodes([BinaryNode])
		case string(String)
		case data(Data)
	}

	public let tag: String
	public let attrs: Attributes
	public let content: Content?

	public init(tag: String, attrs: Attributes = [:], content: Content? = nil) {
		self.tag = tag
		self.attrs = attrs
		self.content = content
	}
}

extension BinaryNode: Equatable {
	public static func == (lhs: BinaryNode, rhs: BinaryNode) -> Bool {
		lhs.tag == rhs.tag && lhs.attrs.unordered == rhs.attrs.unordered && lhs.content == rhs.content
	}
}

public struct BinaryNodeAttributes: ExpressibleByDictionaryLiteral, Sendable, Sequence {
	private var entries: [(String, String)]

	public init() {
		self.entries = []
	}

	public init(_ entries: [(String, String)]) {
		self.entries = entries
	}

	public static func trimmingUndefined(_ entries: [(String, String?)]) -> BinaryNodeAttributes {
		BinaryNodeAttributes(entries.compactMap { key, value in
			value.map { (key, $0) }
		})
	}

	public init(dictionaryLiteral elements: (String, String)...) {
		self.entries = elements
	}

	public subscript(key: String) -> String? {
		entries.last { $0.0 == key }?.1
	}

	public var orderedEntries: [(String, String)] {
		entries
	}

	var unordered: [String: String] {
		Dictionary(uniqueKeysWithValues: entries)
	}

	public func makeIterator() -> IndexingIterator<[(String, String)]> {
		entries.makeIterator()
	}
}

extension BinaryNodeAttributes: Equatable {
	public static func == (lhs: BinaryNodeAttributes, rhs: BinaryNodeAttributes) -> Bool {
		lhs.unordered == rhs.unordered
	}
}

public extension BinaryNode {
	func children(named childTag: String) -> [BinaryNode] {
		guard case let .nodes(children) = content else {
			return []
		}

		return children.filter { $0.tag == childTag }
	}

	func firstChild(named childTag: String) -> BinaryNode? {
		children(named: childTag).first
	}

	func childData(named childTag: String) -> Data? {
		guard let child = firstChild(named: childTag), case let .data(data) = child.content else {
			return nil
		}

		return data
	}

	func childString(named childTag: String) -> String? {
		guard let child = firstChild(named: childTag), let content = child.content else {
			return nil
		}

		switch content {
		case .string(let string):
			return string
		case .data(let data):
			return String(data: data, encoding: .utf8)
		case .nodes:
			return nil
		}
	}

	func unsignedIntegerChild(named childTag: String, length: Int) -> Int? {
		guard let data = childData(named: childTag), data.count >= length else {
			return nil
		}

		return data.prefix(length).reduce(0) { partial, byte in
			256 * partial + Int(byte)
		}
	}
}
