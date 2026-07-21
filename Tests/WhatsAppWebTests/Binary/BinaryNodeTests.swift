import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("BinaryNode")
struct BinaryNodeTests {
	@Test("returns children matching a tag")
	func returnsChildrenMatchingTag() {
		let node = BinaryNode(
			tag: "iq",
			content: .nodes([
				BinaryNode(tag: "group", attrs: ["id": "1"]),
				BinaryNode(tag: "user", attrs: ["id": "2"]),
				BinaryNode(tag: "group", attrs: ["id": "3"])
			])
		)

		#expect(node.children(named: "group").map(\.attrs["id"]) == ["1", "3"])
	}

	@Test("reads string content from string or UTF-8 data children")
	func readsStringContent() throws {
		let text = Data("hello".utf8)
		let node = BinaryNode(
			tag: "message",
			content: .nodes([
				BinaryNode(tag: "body", content: .data(text)),
				BinaryNode(tag: "subject", content: .string("greeting"))
			])
		)

		#expect(node.childString(named: "body") == "hello")
		#expect(node.childString(named: "subject") == "greeting")
	}

	@Test("reads big endian unsigned integers")
	func readsUnsignedIntegers() {
		let node = BinaryNode(
			tag: "root",
			content: .nodes([
				BinaryNode(tag: "value", content: .data(Data([0x01, 0x02, 0x03])))
			])
		)

		#expect(node.unsignedIntegerChild(named: "value", length: 3) == 66_051)
	}

	@Test("trims only missing optional attributes like Baileys trimUndefined")
	func trimsOnlyMissingOptionalAttributesLikeBaileysTrimUndefined() {
		let attrs = BinaryNodeAttributes.trimmingUndefined([
			("missing", nil),
			("empty", ""),
			("zero", "0"),
			("false", "false")
		])

		#expect(attrs["missing"] == nil)
		#expect(attrs["empty"] == "")
		#expect(attrs["zero"] == "0")
		#expect(attrs["false"] == "false")
		#expect(attrs.orderedEntries.map(\.0) == ["empty", "zero", "false"])
	}
}
