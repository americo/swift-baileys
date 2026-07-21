import CryptoKit
import Foundation

public struct LibSignalDeviceSignatureSigner: DeviceSignatureSigning {
	public init() {}

	public func sign(privateKey: Data, message: Data) throws -> Data {
		guard privateKey.count == 32 else {
			throw LibSignalDeviceSignatureSignerError.invalidPrivateKey
		}

		return try XEdDSASigner.sign(privateKey: [UInt8](privateKey), message: [UInt8](message))
	}
}

public enum LibSignalDeviceSignatureSignerError: Error, Equatable, Sendable {
	case invalidPrivateKey
}

private enum XEdDSASigner {
	private static let d2 = field([
		0xf159, 0x26b2, 0x9b94, 0xebd6, 0xb156, 0x8283, 0x149a, 0x00e0,
		0xd130, 0xeef3, 0x80f2, 0x198e, 0xfce7, 0x56df, 0xd9dc, 0x2406
	])
	private static let baseX = field([
		0xd51a, 0x8f25, 0x2d60, 0xc956, 0xa7b2, 0x9525, 0xc760, 0x692c,
		0xdc5c, 0xfdd6, 0xe231, 0xc0a4, 0x53fe, 0xcd6e, 0x36d3, 0x2169
	])
	private static let baseY = field([
		0x6658, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666,
		0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666
	])
	private static let order = [
		0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58,
		0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10
	]

	static func sign(privateKey: [UInt8], message: [UInt8]) throws -> Data {
		var expandedSecret = Array(repeating: UInt8(0), count: 64)
		for index in 0..<32 {
			expandedSecret[index] = privateKey[index]
		}

		expandedSecret[0] &= 248
		expandedSecret[31] &= 127
		expandedSecret[31] |= 64

		var publicPoint = Point()
		scalarBase(&publicPoint, Array(expandedSecret[0..<32]))
		var publicKey = Array(repeating: UInt8(0), count: 32)
		pack(&publicKey, publicPoint)
		for index in 0..<32 {
			expandedSecret[32 + index] = publicKey[index]
		}

		let signBit = expandedSecret[63] & 128
		var signedMessage = Array(repeating: UInt8(0), count: 64 + message.count)
		for index in 0..<message.count {
			signedMessage[64 + index] = message[index]
		}

		for index in 0..<32 {
			signedMessage[32 + index] = expandedSecret[index]
		}

		var nonce = sha512(Array(signedMessage[32..<(64 + message.count)]))
		reduce(&nonce)
		scalarBase(&publicPoint, Array(nonce[0..<32]))
		pack(&signedMessage, publicPoint)

		for index in 0..<32 {
			signedMessage[32 + index] = expandedSecret[32 + index]
		}

		var challenge = sha512(Array(signedMessage[0..<(64 + message.count)]))
		reduce(&challenge)

		var reduced = Array(repeating: 0.0, count: 64)
		for index in 0..<32 {
			reduced[index] = Double(nonce[index])
		}

		for left in 0..<32 {
			for right in 0..<32 {
				reduced[left + right] += Double(challenge[left]) * Double(expandedSecret[right])
			}
		}

		modL(&signedMessage, offset: 32, reduced)
		signedMessage[63] |= signBit
		return Data(signedMessage[0..<64])
	}

	private static func sha512(_ bytes: [UInt8]) -> [UInt8] {
		Array(SHA512.hash(data: Data(bytes)))
	}

	private static func scalarBase(_ point: inout Point, _ scalar: [UInt8]) {
		var base = Point()
		base[0] = baseX
		base[1] = baseY
		base[2] = field([1])
		multiply(&base[3], baseX, baseY)
		scalarMultiply(&point, base, scalar)
	}

	private static func scalarMultiply(_ point: inout Point, _ source: Point, _ scalar: [UInt8]) {
		var base = source
		point = Point()
		point[1] = field([1])
		point[2] = field([1])

		for bitIndex in stride(from: 255, through: 0, by: -1) {
			let bit = Int((scalar[bitIndex / 8] >> UInt8(bitIndex & 7)) & 1)
			conditionalSwap(&point, &base, bit)
			add(&base, point)
			add(&point, point)
			conditionalSwap(&point, &base, bit)
		}
	}

	private static func add(_ point: inout Point, _ other: Point) {
		var a = FieldElement()
		var b = FieldElement()
		var c = FieldElement()
		var d = FieldElement()
		var e = FieldElement()
		var f = FieldElement()
		var g = FieldElement()
		var h = FieldElement()
		var t = FieldElement()

		subtract(&a, point[1], point[0])
		subtract(&t, other[1], other[0])
		multiply(&a, a, t)
		addField(&b, point[0], point[1])
		addField(&t, other[0], other[1])
		multiply(&b, b, t)
		multiply(&c, point[3], other[3])
		multiply(&c, c, d2)
		multiply(&d, point[2], other[2])
		addField(&d, d, d)
		subtract(&e, b, a)
		subtract(&f, d, c)
		addField(&g, d, c)
		addField(&h, b, a)
		multiply(&point[0], e, f)
		multiply(&point[1], h, g)
		multiply(&point[2], g, f)
		multiply(&point[3], e, h)
	}

	private static func pack(_ output: inout [UInt8], _ point: Point) {
		var tx = FieldElement()
		var ty = FieldElement()
		var zi = FieldElement()
		invert(&zi, point[2])
		multiply(&tx, point[0], zi)
		multiply(&ty, point[1], zi)
		packField(&output, ty)
		output[31] ^= UInt8(parity(tx) << 7)
	}

	private static func modL(_ output: inout [UInt8], offset: Int, _ input: [Double]) {
		var x = input
		var carry: Int
		var j = 0
		var k = 0

		for index in stride(from: 63, through: 32, by: -1) {
			carry = 0
			j = index - 32
			k = index - 12
			while j < k {
				x[j] += Double(carry - 16 * Int(x[index]) * order[j - (index - 32)])
				carry = (Int(x[j]) + 128) >> 8
				x[j] -= Double(carry * 256)
				j += 1
			}

			x[j] += Double(carry)
			x[index] = 0
		}

		carry = 0
		for index in 0..<32 {
			x[index] += Double(carry - (Int(x[31]) >> 4) * order[index])
			carry = Int(x[index]) >> 8
			x[index] = Double(Int(x[index]) & 255)
		}

		for index in 0..<32 {
			x[index] -= Double(carry * order[index])
		}

		for index in 0..<32 {
			x[index + 1] += Double(Int(x[index]) >> 8)
			output[offset + index] = UInt8(Int(x[index]) & 255)
		}
	}

	private static func reduce(_ value: inout [UInt8]) {
		var expanded = Array(repeating: 0.0, count: 64)
		for index in 0..<64 {
			expanded[index] = Double(value[index])
			value[index] = 0
		}

		modL(&value, offset: 0, expanded)
	}

	private static func packField(_ output: inout [UInt8], _ input: FieldElement) {
		var m = FieldElement()
		var t = input
		carry(&t)
		carry(&t)
		carry(&t)

		for _ in 0..<2 {
			m[0] = t[0] - 0xffed
			for index in 1..<15 {
				m[index] = t[index] - 0xffff - Double((Int(m[index - 1]) >> 16) & 1)
				m[index - 1] = Double(Int(m[index - 1]) & 0xffff)
			}

			m[15] = t[15] - 0x7fff - Double((Int(m[14]) >> 16) & 1)
			let bit = (Int(m[15]) >> 16) & 1
			m[14] = Double(Int(m[14]) & 0xffff)
			select(&t, &m, 1 - bit)
		}

		for index in 0..<16 {
			output[2 * index] = UInt8(Int(t[index]) & 0xff)
			output[2 * index + 1] = UInt8((Int(t[index]) >> 8) & 0xff)
		}
	}

	private static func parity(_ value: FieldElement) -> Int {
		var packed = Array(repeating: UInt8(0), count: 32)
		packField(&packed, value)
		return Int(packed[0] & 1)
	}

	private static func invert(_ output: inout FieldElement, _ input: FieldElement) {
		var value = input
		for exponent in stride(from: 253, through: 0, by: -1) {
			square(&value, value)
			if exponent != 2, exponent != 4 {
				multiply(&value, value, input)
			}
		}

		output = value
	}

	private static func square(_ output: inout FieldElement, _ value: FieldElement) {
		multiply(&output, value, value)
	}

	private static func multiply(_ output: inout FieldElement, _ first: FieldElement, _ second: FieldElement) {
		var terms = Array(repeating: 0.0, count: 31)
		for firstIndex in 0..<16 {
			for secondIndex in 0..<16 {
				terms[firstIndex + secondIndex] += first[firstIndex] * second[secondIndex]
			}
		}

		for index in 0..<15 {
			terms[index] += 38 * terms[index + 16]
		}

		var reduced = FieldElement()
		for index in 0..<16 {
			reduced[index] = terms[index]
		}

		carry(&reduced)
		carry(&reduced)
		output = reduced
	}

	private static func carry(_ output: inout FieldElement) {
		var carry = 1.0
		for index in 0..<16 {
			let value = output[index] + carry + 65535
			carry = floor(value / 65536)
			output[index] = value - carry * 65536
		}

		output[0] += carry - 1 + 37 * (carry - 1)
	}

	private static func conditionalSwap(_ first: inout Point, _ second: inout Point, _ bit: Int) {
		for index in 0..<4 {
			select(&first[index], &second[index], bit)
		}
	}

	private static func select(_ first: inout FieldElement, _ second: inout FieldElement, _ bit: Int) {
		let mask = ~(bit - 1)
		for index in 0..<16 {
			let value = mask & (Int(first[index]) ^ Int(second[index]))
			first[index] = Double(Int(first[index]) ^ value)
			second[index] = Double(Int(second[index]) ^ value)
		}
	}

	private static func addField(_ output: inout FieldElement, _ first: FieldElement, _ second: FieldElement) {
		for index in 0..<16 {
			output[index] = first[index] + second[index]
		}
	}

	private static func subtract(_ output: inout FieldElement, _ first: FieldElement, _ second: FieldElement) {
		for index in 0..<16 {
			output[index] = first[index] - second[index]
		}
	}

	private static func field(_ values: [Double] = []) -> FieldElement {
		FieldElement(values)
	}
}

private typealias Point = [FieldElement]

private extension Point {
	init() {
		self = Array(repeating: FieldElement(), count: 4)
	}
}

private struct FieldElement {
	private var limbs: [Double]

	init(_ values: [Double] = []) {
		limbs = Array(repeating: 0, count: 16)
		for (index, value) in values.enumerated() where index < 16 {
			limbs[index] = value
		}
	}

	subscript(index: Int) -> Double {
		get {
			limbs[index]
		}
		set {
			limbs[index] = newValue
		}
	}
}
