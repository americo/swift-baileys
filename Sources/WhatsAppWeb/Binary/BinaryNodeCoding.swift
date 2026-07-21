import Foundation

public enum BinaryNodeCodingError: Error, Equatable {
	case compressedPayloadUnsupported
	case endOfStream
	case invalidHexLength
	case invalidListTag(UInt8)
	case invalidNode
	case invalidPackedCharacter(Character)
	case invalidStringTag(UInt8)
	case stringTooLarge(Int)
	case unsupportedContent
}

public struct BinaryNodeEncoder: Sendable {
	public init() {}

	public func encode(_ node: BinaryNode) throws -> Data {
		var writer = BinaryNodeWriter()
		writer.writeByte(0)
		try writer.write(node)
		return writer.data
	}
}

public struct BinaryNodeDecoder: Sendable {
	public init() {}

	public func decode(_ data: Data) throws -> BinaryNode {
		guard let firstByte = data.first else {
			throw BinaryNodeCodingError.endOfStream
		}

		let payload = firstByte & 2 == 2 ? try BinaryNodeCompression.inflate(Data(data.dropFirst())) : Data(data.dropFirst())
		var reader = BinaryNodeReader(data: payload)
		return try reader.readNode()
	}
}

private enum BinaryNodeTag {
	static let listEmpty: UInt8 = 0
	static let dictionary0: UInt8 = 236
	static let dictionary1: UInt8 = 237
	static let dictionary2: UInt8 = 238
	static let dictionary3: UInt8 = 239
	static let interopJID: UInt8 = 245
	static let fbJID: UInt8 = 246
	static let adJID: UInt8 = 247
	static let list8: UInt8 = 248
	static let list16: UInt8 = 249
	static let jidPair: UInt8 = 250
	static let hex8: UInt8 = 251
	static let binary8: UInt8 = 252
	static let binary20: UInt8 = 253
	static let binary32: UInt8 = 254
	static let nibble8: UInt8 = 255
	static let packedMax = 127
}

private struct BinaryNodeWriter {
	private(set) var data = Data()

	mutating func writeByte(_ value: UInt8) {
		data.append(value)
	}

	mutating func write(_ node: BinaryNode) throws {
		let attrs = node.attrs.orderedEntries
			.filter { !$0.0.isEmpty }
		let listSize = 2 * attrs.count + 1 + (node.content == nil ? 0 : 1)

		try writeListStart(size: listSize)
		try writeString(node.tag)

		for attr in attrs {
			try writeString(attr.0)
			try writeString(attr.1)
		}

		switch node.content {
		case .string(let value):
			try writeString(value)
		case .data(let value):
			try writeByteLength(value.count)
			data.append(value)
		case .nodes(let children):
			try writeListStart(size: children.count)
			for child in children {
				try write(child)
			}
		case nil:
			break
		}
	}

	private mutating func writeListStart(size: Int) throws {
		if size == 0 {
			writeByte(BinaryNodeTag.listEmpty)
		} else if size < 256 {
			writeByte(BinaryNodeTag.list8)
			writeByte(UInt8(size))
		} else {
			writeByte(BinaryNodeTag.list16)
			writeByte(UInt8((size >> 8) & 0xff))
			writeByte(UInt8(size & 0xff))
		}
	}

	private mutating func writeString(_ value: String) throws {
		if value.isEmpty {
			try writeStringRaw(value)
		} else if let token = BinaryNodeTokens.shared.singleByteByString[value] {
			writeByte(token)
		} else if let token = BinaryNodeTokens.shared.doubleByteByString[value] {
			writeByte(BinaryNodeTag.dictionary0 + token.dictionary)
			writeByte(token.index)
		} else if isNibble(value) {
			try writePackedBytes(value, tag: BinaryNodeTag.nibble8, pack: packNibble)
		} else if isHex(value) {
			try writePackedBytes(value, tag: BinaryNodeTag.hex8, pack: packHex)
		} else if let jid = JID(value) {
			try writeJID(jid)
		} else {
			try writeStringRaw(value)
		}
	}

	private mutating func writeStringRaw(_ value: String) throws {
		let bytes = Data(value.utf8)
		try writeByteLength(bytes.count)
		data.append(bytes)
	}

	private mutating func writeJID(_ jid: JID) throws {
		if let device = jid.device {
			writeByte(BinaryNodeTag.adJID)
			writeByte(UInt8(jid.domainType.rawValue))
			writeByte(UInt8(device))
			try writeString(jid.user)
		} else {
			writeByte(BinaryNodeTag.jidPair)
			if jid.user.isEmpty {
				writeByte(BinaryNodeTag.listEmpty)
			} else {
				try writeString(jid.user)
			}

			try writeString(jid.server)
		}
	}

	private mutating func writePackedBytes(
		_ value: String,
		tag: UInt8,
		pack: (Character) throws -> UInt8
	) throws {
		writeByte(tag)

		var roundedLength = UInt8((value.count + 1) / 2)
		if value.count % 2 != 0 {
			roundedLength |= 128
		}

		writeByte(roundedLength)

		let chars = Array(value)
		for index in stride(from: 0, to: chars.count - (chars.count % 2), by: 2) {
			writeByte(try packBytePair(chars[index], chars[index + 1], pack: pack))
		}

		if let last = chars.last, value.count % 2 != 0 {
			writeByte(try packBytePair(last, "\0", pack: pack))
		}
	}

	private func packBytePair(
		_ first: Character,
		_ second: Character,
		pack: (Character) throws -> UInt8
	) throws -> UInt8 {
		(try pack(first) << 4) | (try pack(second))
	}

	private func packNibble(_ character: Character) throws -> UInt8 {
		switch character {
		case "-":
			return 10
		case ".":
			return 11
		case "\0":
			return 15
		case "0"..."9":
			return UInt8(String(character)) ?? 0
		default:
			throw BinaryNodeCodingError.invalidPackedCharacter(character)
		}
	}

	private func packHex(_ character: Character) throws -> UInt8 {
		switch character {
		case "0"..."9":
			return UInt8(String(character)) ?? 0
		case "A"..."F":
			return 10 + UInt8(character.asciiValue! - Character("A").asciiValue!)
		case "a"..."f":
			return 10 + UInt8(character.asciiValue! - Character("a").asciiValue!)
		case "\0":
			return 15
		default:
			throw BinaryNodeCodingError.invalidPackedCharacter(character)
		}
	}

	private func isNibble(_ value: String) -> Bool {
		value.count <= BinaryNodeTag.packedMax && value.allSatisfy { character in
			("0"..."9").contains(character) || character == "-" || character == "."
		}
	}

	private func isHex(_ value: String) -> Bool {
		value.count <= BinaryNodeTag.packedMax && value.allSatisfy { character in
			("0"..."9").contains(character) || ("A"..."F").contains(character)
		}
	}

	private mutating func writeByteLength(_ length: Int) throws {
		if length >= 4_294_967_296 {
			throw BinaryNodeCodingError.stringTooLarge(length)
		}

		if length >= 1 << 20 {
			writeByte(BinaryNodeTag.binary32)
			writeByte(UInt8((length >> 24) & 0xff))
			writeByte(UInt8((length >> 16) & 0xff))
			writeByte(UInt8((length >> 8) & 0xff))
			writeByte(UInt8(length & 0xff))
		} else if length >= 256 {
			writeByte(BinaryNodeTag.binary20)
			writeByte(UInt8((length >> 16) & 0x0f))
			writeByte(UInt8((length >> 8) & 0xff))
			writeByte(UInt8(length & 0xff))
		} else {
			writeByte(BinaryNodeTag.binary8)
			writeByte(UInt8(length))
		}
	}
}

private struct BinaryNodeReader {
	let data: Data
	var index = 0

	mutating func readNode() throws -> BinaryNode {
		let listSize = try readListSize(tag: readByte())
		let header = try readString(tag: readByte())

		guard listSize > 0, !header.isEmpty else {
			throw BinaryNodeCodingError.invalidNode
		}

		var attrEntries: [(String, String)] = []
		let attributesLength = (listSize - 1) >> 1
		for _ in 0..<attributesLength {
			attrEntries.append((try readString(tag: readByte()), try readString(tag: readByte())))
		}
		let attrs = BinaryNode.Attributes(attrEntries)

		if listSize % 2 == 0 {
			return BinaryNode(tag: header, attrs: attrs, content: try readContent())
		}

		return BinaryNode(tag: header, attrs: attrs)
	}

	private mutating func readContent() throws -> BinaryNode.Content {
		let tag = try readByte()

		switch tag {
		case BinaryNodeTag.listEmpty, BinaryNodeTag.list8, BinaryNodeTag.list16:
			return .nodes(try readList(tag: tag))
		case BinaryNodeTag.binary8:
			return .data(try readBytes(count: Int(readByte())))
		case BinaryNodeTag.binary20:
			return .data(try readBytes(count: readInt20()))
		case BinaryNodeTag.binary32:
			return .data(try readBytes(count: readInt(byteCount: 4)))
		default:
			return .string(try readString(tag: tag))
		}
	}

	private mutating func readList(tag: UInt8) throws -> [BinaryNode] {
		let size = try readListSize(tag: tag)
		var items: [BinaryNode] = []
		items.reserveCapacity(size)

		for _ in 0..<size {
			items.append(try readNode())
		}

		return items
	}

	private mutating func readString(tag: UInt8) throws -> String {
		let tokenIndex = Int(tag)
		if BinaryNodeTokens.shared.singleByte.indices.contains(tokenIndex) {
			let token = BinaryNodeTokens.shared.singleByte[tokenIndex]
			if !token.isEmpty {
				return token
			}
		}

		switch tag {
		case BinaryNodeTag.dictionary0...BinaryNodeTag.dictionary3:
			let dictionary = Int(tag - BinaryNodeTag.dictionary0)
			let index = Int(try readByte())
			return try BinaryNodeTokens.shared.doubleByteToken(dictionary: dictionary, index: index)
		case BinaryNodeTag.listEmpty:
			return ""
		case BinaryNodeTag.binary8:
			return try readUTF8String(count: Int(readByte()))
		case BinaryNodeTag.binary20:
			return try readUTF8String(count: readInt20())
		case BinaryNodeTag.binary32:
			return try readUTF8String(count: readInt(byteCount: 4))
		case BinaryNodeTag.jidPair:
			return try readJIDPair()
		case BinaryNodeTag.fbJID:
			return try readFBJID()
		case BinaryNodeTag.interopJID:
			return try readInteropJID()
		case BinaryNodeTag.adJID:
			return try readADJID()
		case BinaryNodeTag.hex8, BinaryNodeTag.nibble8:
			return try readPacked8(tag: tag)
		default:
			throw BinaryNodeCodingError.invalidStringTag(tag)
		}
	}

	private mutating func readJIDPair() throws -> String {
		let user = try readString(tag: readByte())
		let server = try readString(tag: readByte())

		guard !server.isEmpty else {
			throw BinaryNodeCodingError.invalidNode
		}

		return "\(user)@\(server)"
	}

	private mutating func readFBJID() throws -> String {
		let user = try readString(tag: readByte())
		let device = try readInt(byteCount: 2)
		let server = try readString(tag: readByte())
		return "\(user):\(device)@\(server)"
	}

	private mutating func readInteropJID() throws -> String {
		let user = try readString(tag: readByte())
		let device = try readInt(byteCount: 2)
		let integrator = try readInt(byteCount: 2)
		let server = try readOptionalTrailingString(defaultValue: "interop")
		return "\(integrator)-\(user):\(device)@\(server)"
	}

	private mutating func readADJID() throws -> String {
		let domainType = Int(try readByte())
		let device = Int(try readByte())
		let user = try readString(tag: readByte())
		let server: String

		switch JIDDomainType(rawValue: domainType) {
		case .lid:
			server = JIDServer.lid.rawValue
		case .hosted:
			server = JIDServer.hosted.rawValue
		case .hostedLid:
			server = JIDServer.hostedLid.rawValue
		case .whatsapp, nil:
			server = JIDServer.user.rawValue
		}

		return JID.encode(user: user, server: server, device: device)
	}

	private mutating func readOptionalTrailingString(defaultValue: String) throws -> String {
		let savedIndex = index

		do {
			return try readString(tag: readByte())
		} catch {
			index = savedIndex
			return defaultValue
		}
	}

	private mutating func readPacked8(tag: UInt8) throws -> String {
		let startByte = try readByte()
		var value = ""

		for _ in 0..<(startByte & 127) {
			let currentByte = try readByte()
			value.append(try unpackByte(tag: tag, value: (currentByte & 0xf0) >> 4))
			value.append(try unpackByte(tag: tag, value: currentByte & 0x0f))
		}

		if startByte >> 7 != 0 {
			value.removeLast()
		}

		return value
	}

	private func unpackByte(tag: UInt8, value: UInt8) throws -> Character {
		switch tag {
		case BinaryNodeTag.nibble8:
			return try unpackNibble(value)
		case BinaryNodeTag.hex8:
			return try unpackHex(value)
		default:
			throw BinaryNodeCodingError.invalidStringTag(tag)
		}
	}

	private func unpackNibble(_ value: UInt8) throws -> Character {
		switch value {
		case 0...9:
			return Character(String(value))
		case 10:
			return "-"
		case 11:
			return "."
		case 15:
			return "\0"
		default:
			throw BinaryNodeCodingError.invalidPackedCharacter(Character(String(value)))
		}
	}

	private func unpackHex(_ value: UInt8) throws -> Character {
		switch value {
		case 0...9:
			return Character(String(value))
		case 10...15:
			let scalar = UnicodeScalar(UInt8(ascii: "A") + value - 10)
			return Character(scalar)
		default:
			throw BinaryNodeCodingError.invalidPackedCharacter(Character(String(value)))
		}
	}

	private mutating func readListSize(tag: UInt8) throws -> Int {
		switch tag {
		case BinaryNodeTag.listEmpty:
			return 0
		case BinaryNodeTag.list8:
			return Int(try readByte())
		case BinaryNodeTag.list16:
			return try readInt(byteCount: 2)
		default:
			throw BinaryNodeCodingError.invalidListTag(tag)
		}
	}

	private mutating func readByte() throws -> UInt8 {
		guard index < data.count else {
			throw BinaryNodeCodingError.endOfStream
		}

		defer { index += 1 }
		return data[index]
	}

	private mutating func readBytes(count: Int) throws -> Data {
		guard index + count <= data.count else {
			throw BinaryNodeCodingError.endOfStream
		}

		defer { index += count }
		return data.subdata(in: index..<(index + count))
	}

	private mutating func readUTF8String(count: Int) throws -> String {
		String(data: try readBytes(count: count), encoding: .utf8) ?? ""
	}

	private mutating func readInt(byteCount: Int) throws -> Int {
		var value = 0
		for _ in 0..<byteCount {
			value = 256 * value + Int(try readByte())
		}

		return value
	}

	private mutating func readInt20() throws -> Int {
		let first = Int(try readByte() & 0x0f)
		return (first << 16) + (Int(try readByte()) << 8) + Int(try readByte())
	}
}
