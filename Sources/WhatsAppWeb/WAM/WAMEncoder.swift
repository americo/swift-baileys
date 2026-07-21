import Foundation

public enum WAMValue: Equatable, Sendable {
	case integer(Int64)
	case double(Double)
	case string(String)
	case bool(Bool)
	case null
}

public struct WAMGlobalDefinition: Equatable, Sendable {
	public let name: String
	public let id: Int

	public init(name: String, id: Int) {
		self.name = name
		self.id = id
	}
}

public struct WAMEventDefinition: Equatable, Sendable {
	public let name: String
	public let id: Int
	public let weight: Int
	public let props: [String: Int]

	public init(name: String, id: Int, weight: Int, props: [String: Int]) {
		self.name = name
		self.id = id
		self.weight = weight
		self.props = props
	}
}

public struct WAMEventInput: Sendable {
	public let name: String
	public let props: [(String, WAMValue)]
	public let globals: [(String, WAMValue)]

	public init(name: String, props: [(String, WAMValue)] = [], globals: [(String, WAMValue)] = []) {
		self.name = name
		self.props = props
		self.globals = globals
	}
}

public struct WAMBinaryInfo: Sendable {
	public var protocolVersion: UInt8
	public var sequence: UInt16
	public var events: [WAMEventInput]

	public init(protocolVersion: UInt8 = 5, sequence: UInt16 = 0, events: [WAMEventInput] = []) {
		self.protocolVersion = protocolVersion
		self.sequence = sequence
		self.events = events
	}
}

public enum WAMEncodingError: Error, Equatable, Sendable {
	case unknownGlobal(String)
	case unknownEvent(String)
	case unknownEventProperty(event: String, property: String)
	case invalidKey(Int)
	case unsupportedNullValue
}

public enum WAMEncoder {
	private static let flagByte = 8
	private static let flagGlobal = 0
	private static let flagEvent = 1
	private static let flagField = 2
	private static let flagExtended = 4

	public static func encode(_ binaryInfo: WAMBinaryInfo) throws -> Data {
		try encode(binaryInfo, definitions: WAMDefinitions.web())
	}

	public static func encode(
		_ binaryInfo: WAMBinaryInfo,
		events eventDefinitions: [WAMEventDefinition],
		globals globalDefinitions: [WAMGlobalDefinition] = []
	) throws -> Data {
		try encode(binaryInfo, definitions: WAMDefinitions(events: eventDefinitions, globals: globalDefinitions))
	}

	public static func encode(
		_ binaryInfo: WAMBinaryInfo,
		definitions: WAMDefinitions
	) throws -> Data {
		let eventDefinitions = definitions.events
		let globalDefinitions = definitions.globals
		let eventsByName = Dictionary(uniqueKeysWithValues: eventDefinitions.map { ($0.name, $0) })
		let globalsByName = Dictionary(uniqueKeysWithValues: globalDefinitions.map { ($0.name, $0) })
		var data = Data([
			0x57, 0x41, 0x4d,
			binaryInfo.protocolVersion,
			0x01,
			UInt8(binaryInfo.sequence >> 8),
			UInt8(binaryInfo.sequence & 0xff),
			0x00
		])

		for input in binaryInfo.events {
			for (name, value) in input.globals {
				guard let global = globalsByName[name] else {
					throw WAMEncodingError.unknownGlobal(name)
				}

				try data.append(serialize(key: global.id, value: value, flag: flagGlobal))
			}

			guard let event = eventsByName[input.name] else {
				throw WAMEncodingError.unknownEvent(input.name)
			}

			let hasNonNullProp = input.props.contains { $0.1 != .null }
			let eventFlag = hasNonNullProp ? flagEvent : flagEvent | flagExtended
			try data.append(serialize(key: event.id, value: .integer(Int64(-event.weight)), flag: eventFlag))

			for (index, prop) in input.props.enumerated() {
				guard let propertyID = event.props[prop.0] else {
					throw WAMEncodingError.unknownEventProperty(event: input.name, property: prop.0)
				}

				let fieldFlag = index < input.props.count - 1 ? flagEvent : flagField | flagExtended
				try data.append(serialize(key: propertyID, value: prop.1, flag: fieldFlag))
			}
		}

		return data
	}

	private static func serialize(key: Int, value: WAMValue, flag: Int) throws -> Data {
		guard key >= 0 && key <= UInt16.max else {
			throw WAMEncodingError.invalidKey(key)
		}

		switch value {
		case .null:
			guard flag == flagGlobal else {
				throw WAMEncodingError.unsupportedNullValue
			}

			return header(key: key, flag: flag)
		case .bool(let bool):
			return try serialize(key: key, value: .integer(bool ? 1 : 0), flag: flag)
		case .integer(let value):
			if value == 0 || value == 1 {
				return header(key: key, flag: flag | (Int(value + 1) << 4))
			}

			if value >= Int64(Int8.min) && value < Int64(Int8.max) + 1 {
				var data = header(key: key, flag: flag | (3 << 4))
				data.append(UInt8(bitPattern: Int8(value)))
				return data
			}

			if value >= Int64(Int16.min) && value < Int64(Int16.max) + 1 {
				var data = header(key: key, flag: flag | (4 << 4))
				var littleEndian = Int16(value).littleEndian
				withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
				return data
			}

			if value >= Int64(Int32.min) && value < Int64(Int32.max) + 1 {
				var data = header(key: key, flag: flag | (5 << 4))
				var littleEndian = Int32(value).littleEndian
				withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
				return data
			}

			return doubleData(key: key, value: Double(value), flag: flag)
		case .double(let value):
			return doubleData(key: key, value: value, flag: flag)
		case .string(let value):
			let bytes = Data(value.utf8)
			if bytes.count < 256 {
				var data = header(key: key, flag: flag | (8 << 4))
				data.append(UInt8(bytes.count))
				data.append(bytes)
				return data
			}

			if bytes.count < 65_536 {
				var data = header(key: key, flag: flag | (9 << 4))
				var length = UInt16(bytes.count).littleEndian
				withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
				data.append(bytes)
				return data
			}

			var data = header(key: key, flag: flag | (10 << 4))
			var length = UInt32(bytes.count).littleEndian
			withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
			data.append(bytes)
			return data
		}
	}

	private static func doubleData(key: Int, value: Double, flag: Int) -> Data {
		var data = header(key: key, flag: flag | (7 << 4))
		var littleEndian = value.bitPattern.littleEndian
		withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
		return data
	}

	private static func header(key: Int, flag: Int) -> Data {
		if key < 256 {
			return Data([UInt8(flag), UInt8(key)])
		}

		return Data([
			UInt8(flag | flagByte),
			UInt8(key & 0xff),
			UInt8((key >> 8) & 0xff)
		])
	}
}
