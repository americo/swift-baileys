import Foundation

enum MessagePadding {
	static func padded(_ data: Data, randomByte: () throws -> UInt8) throws -> Data {
		var paddedData = data
		let padLength = Int(try randomByte() & 0x0f) + 1
		paddedData.append(contentsOf: repeatElement(UInt8(padLength), count: padLength))
		return paddedData
	}

	static func unpadded(_ data: Data) throws -> Data {
		guard let paddingLength = data.last else {
			throw MessagePaddingError.emptyPaddedMessage
		}

		guard paddingLength <= data.count else {
			throw MessagePaddingError.invalidPadding
		}

		return data.dropLast(Int(paddingLength))
	}
}

enum MessagePaddingError: Error, Equatable, Sendable {
	case emptyPaddedMessage
	case invalidPadding
}
