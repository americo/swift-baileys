import Foundation

func hexData(_ hexString: String) throws -> Data {
	var bytes: [UInt8] = []
	var index = hexString.startIndex

	while index < hexString.endIndex {
		let next = hexString.index(index, offsetBy: 2)
		guard let byte = UInt8(hexString[index..<next], radix: 16) else {
			throw HexDataTestSupportError.invalidHex
		}

		bytes.append(byte)
		index = next
	}

	return Data(bytes)
}

enum HexDataTestSupportError: Error {
	case invalidHex
}
