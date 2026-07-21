import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("BinaryNode coding")
struct BinaryNodeCodingTests {
	@Test("encodes a raw string node using the Baileys binary framing")
	func encodesRawStringNode() throws {
		let node = BinaryNode(
			tag: "zz_root",
			attrs: ["zz_key": "zz_value"],
			content: .string("zz_text")
		)

		let encoded = try BinaryNodeEncoder().encode(node)

		#expect(encoded.hexString == "00f804fc077a7a5f726f6f74fc067a7a5f6b6579fc087a7a5f76616c7565fc077a7a5f74657874")
	}

	@Test("decodes raw binary payloads as data using the Baileys binary framing")
	func decodesRawStringNode() throws {
		let data = try Data(hexString: "00f804fc077a7a5f726f6f74fc067a7a5f6b6579fc087a7a5f76616c7565fc077a7a5f74657874")

		let decoded = try BinaryNodeDecoder().decode(data)

		#expect(decoded == BinaryNode(
			tag: "zz_root",
			attrs: ["zz_key": "zz_value"],
			content: .data(Data("zz_text".utf8))
		))
	}

	@Test("roundtrips nested child nodes")
	func roundtripsNestedChildNodes() throws {
		let node = BinaryNode(
			tag: "zz_parent",
			content: .nodes([
				BinaryNode(tag: "zz_child", attrs: ["zz_id": "abc"])
			])
		)

		let decoded = try BinaryNodeDecoder().decode(BinaryNodeEncoder().encode(node))

		#expect(decoded == node)
	}

	@Test("encodes nibble packed strings like Baileys")
	func encodesNibblePackedStrings() throws {
		let node = BinaryNode(tag: "zz_root", attrs: ["zz_phone": "258840000000"])

		let encoded = try BinaryNodeEncoder().encode(node)

		#expect(encoded.hexString == "00f803fc077a7a5f726f6f74fc087a7a5f70686f6e65ff06258840000000")
		#expect(try BinaryNodeDecoder().decode(encoded) == node)
	}

	@Test("encodes hex packed strings like Baileys")
	func encodesHexPackedStrings() throws {
		let node = BinaryNode(tag: "zz_root", attrs: ["zz_hex": "A1B2"])

		let encoded = try BinaryNodeEncoder().encode(node)

		#expect(encoded.hexString == "00f803fc077a7a5f726f6f74fc067a7a5f686578fb02a1b2")
		#expect(try BinaryNodeDecoder().decode(encoded) == node)
	}

	@Test("encodes JID pair strings like Baileys")
	func encodesJIDPairStrings() throws {
		let node = BinaryNode(tag: "zz_root", attrs: ["zz_jid": "258840000000@s.whatsapp.net"])

		let encoded = try BinaryNodeEncoder().encode(node)

		#expect(encoded.hexString == "00f803fc077a7a5f726f6f74fc067a7a5f6a6964faff0625884000000003")
		#expect(try BinaryNodeDecoder().decode(encoded) == node)
	}

	@Test("encodes device JID strings like Baileys")
	func encodesDeviceJIDStrings() throws {
		let node = BinaryNode(tag: "zz_root", attrs: ["zz_jid": "258840000000:42@s.whatsapp.net"])

		let encoded = try BinaryNodeEncoder().encode(node)

		#expect(encoded.hexString == "00f803fc077a7a5f726f6f74fc067a7a5f6a6964f7002aff06258840000000")
		#expect(try BinaryNodeDecoder().decode(encoded) == node)
	}

	@Test("encodes single byte tokens using Baileys token table")
	func encodesSingleByteTokens() throws {
		let node = BinaryNode(
			tag: "notification",
			attrs: [
				"type": "server_sync",
				"jid": "258840000000@s.whatsapp.net"
			]
		)

		let encoded = try BinaryNodeEncoder().encode(node)

		#expect(encoded.hexString == "00f8050904eccb0cfaff0625884000000003")
		#expect(try BinaryNodeDecoder().decode(encoded) == node)
	}

	@Test("encodes double byte tokens using Baileys token table")
	func encodesDoubleByteTokens() throws {
		let node = BinaryNode(
			tag: "iq",
			attrs: [
				"xmlns": "w:sync:app:state",
				"type": "get"
			],
			content: .nodes([
				BinaryNode(tag: "collection", attrs: ["name": "critical_block"])
			])
		)

		let encoded = try BinaryNodeEncoder().encode(node)

		#expect(encoded.hexString == "00f8061916ec9c0429f801f803ec5b89eea1")
		#expect(try BinaryNodeDecoder().decode(encoded) == node)
	}

	@Test("decodes FB JID strings from incoming Baileys binary nodes")
	func decodesFBJIDStrings() throws {
		let data = try Data(hexString: "00f803fc077a7a5f726f6f74fc067a7a5f6a6964f6ff06258840000000002a03")

		let decoded = try BinaryNodeDecoder().decode(data)

		#expect(decoded == BinaryNode(
			tag: "zz_root",
			attrs: ["zz_jid": "258840000000:42@s.whatsapp.net"]
		))
	}

	@Test("decodes interop JID strings from incoming Baileys binary nodes")
	func decodesInteropJIDStrings() throws {
		let data = try Data(hexString: "00f803fc077a7a5f726f6f74fc067a7a5f6a6964f5ff06258840000000002a000703")

		let decoded = try BinaryNodeDecoder().decode(data)

		#expect(decoded == BinaryNode(
			tag: "zz_root",
			attrs: ["zz_jid": "7-258840000000:42@s.whatsapp.net"]
		))
	}

	@Test("decodes zlib compressed Baileys binary nodes")
	func decodesCompressedBinaryNodes() throws {
		let data = try Data(hexString: "02789cfbc1cac9f2e634cfafff6caa1d0e0c0c0ccc003ffd05bd")

		let decoded = try BinaryNodeDecoder().decode(data)

		#expect(decoded == BinaryNode(
			tag: "notification",
			attrs: [
				"type": "server_sync",
				"jid": "258840000000@s.whatsapp.net"
			]
		))
	}
}

private extension Data {
	init(hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw BinaryNodeCodingTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}

	var hexString: String {
		map { String(format: "%02x", $0) }.joined()
	}
}

private enum BinaryNodeCodingTestError: Error {
	case invalidHex
}
