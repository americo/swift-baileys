import Foundation

enum BigEndianEncoder {
	static func encode(_ value: Int, count: Int = 4) -> Data {
		var remaining = value
		var bytes = Array(repeating: UInt8(0), count: count)
		for index in stride(from: count - 1, through: 0, by: -1) {
			bytes[index] = UInt8(remaining & 0xff)
			remaining >>= 8
		}

		return Data(bytes)
	}
}
