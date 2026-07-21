import Foundation

enum ByteCrockfordEncoder {
	private static let characters = Array("123456789ABCDEFGHJKLMNPQRSTVWXYZ")

	static func encode(_ data: Data) -> String {
		var value = 0
		var bitCount = 0
		var output = ""

		for byte in data {
			value = (value << 8) | Int(byte)
			bitCount += 8

			while bitCount >= 5 {
				output.append(characters[(value >> (bitCount - 5)) & 31])
				bitCount -= 5
			}

			if bitCount > 0 {
				value &= (1 << bitCount) - 1
			} else {
				value = 0
			}
		}

		if bitCount > 0 {
			output.append(characters[(value << (5 - bitCount)) & 31])
		}

		return output
	}
}
