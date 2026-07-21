import CryptoKit
import Foundation

struct NoiseXEdDSAVerifier: NoiseCertificateVerifying {
	func verify(publicKey: Data, message: Data, signature: Data) -> Bool {
		guard publicKey.count == 32, signature.count == 64 else {
			return false
		}

		do {
			var edwardsPublicKey = convertMontgomeryPublicKey(publicKey)
			var normalizedSignature = signature
			edwardsPublicKey[31] |= normalizedSignature[63] & 0x80
			normalizedSignature[63] &= 0x7f

			let signingKey = try Curve25519.Signing.PublicKey(rawRepresentation: edwardsPublicKey)
			return signingKey.isValidSignature(normalizedSignature, for: message)
		} catch {
			return false
		}
	}

	private func convertMontgomeryPublicKey(_ publicKey: Data) -> Data {
		var z = Data(repeating: 0, count: 32)
		var x = FieldElement()
		var a = FieldElement()
		var b = FieldElement()

		unpack(&x, publicKey)
		add(&a, x, FieldElement.one)
		subtract(&b, x, FieldElement.one)
		invert(&a, a)
		multiply(&a, a, b)
		pack(&z, a)
		return z
	}

	private func unpack(_ output: inout FieldElement, _ data: Data) {
		for index in 0..<16 {
			output[index] = Double(Int(data[2 * index]) + (Int(data[2 * index + 1]) << 8))
		}

		output[15] = Double(Int(output[15]) & 0x7fff)
	}

	private func pack(_ output: inout Data, _ input: FieldElement) {
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

	private func carry(_ output: inout FieldElement) {
		var carry = 1.0
		for index in 0..<16 {
			let value = output[index] + carry + 65535
			carry = floor(value / 65536)
			output[index] = value - carry * 65536
		}

		output[0] += carry - 1 + 37 * (carry - 1)
	}

	private func select(_ first: inout FieldElement, _ second: inout FieldElement, _ bit: Int) {
		let mask = ~(bit - 1)
		for index in 0..<16 {
			let value = mask & (Int(first[index]) ^ Int(second[index]))
			first[index] = Double(Int(first[index]) ^ value)
			second[index] = Double(Int(second[index]) ^ value)
		}
	}

	private func add(_ output: inout FieldElement, _ first: FieldElement, _ second: FieldElement) {
		for index in 0..<16 {
			output[index] = first[index] + second[index]
		}
	}

	private func subtract(_ output: inout FieldElement, _ first: FieldElement, _ second: FieldElement) {
		for index in 0..<16 {
			output[index] = first[index] - second[index]
		}
	}

	private func square(_ output: inout FieldElement, _ value: FieldElement) {
		multiply(&output, value, value)
	}

	private func invert(_ output: inout FieldElement, _ input: FieldElement) {
		var value = input
		for exponent in stride(from: 253, through: 0, by: -1) {
			square(&value, value)
			if exponent != 2, exponent != 4 {
				multiply(&value, value, input)
			}
		}

		output = value
	}

	private func multiply(_ output: inout FieldElement, _ first: FieldElement, _ second: FieldElement) {
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
}

private struct FieldElement {
	static let one = FieldElement([1])

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
