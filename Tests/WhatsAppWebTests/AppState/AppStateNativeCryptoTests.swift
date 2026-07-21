import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Native app-state crypto")
struct AppStateNativeCryptoTests {
	@Test("expands app-state keys like Baileys")
	func expandsAppStateKeysLikeBaileys() throws {
		let keys = try NativeAppStateKeyExpander().expand(keyData: Data((0..<32).map(UInt8.init)))

		#expect(keys.indexKey == (try Data(hexString: "61387bcf643616a68bd611a45516b3980418323087d78bf08c615645549434b4")))
		#expect(keys.valueEncryptionKey == (try Data(hexString: "900ba2843ba5fb0cee55cf2a4de9503dce68187d3f6b95b420b008bde66f5a20")))
		#expect(keys.valueMacKey == (try Data(hexString: "d0879f6b61f0bcba79faad3f47a8a768fd7fc04a6cc8b3ecefedfa087413226f")))
		#expect(keys.snapshotMacKey == (try Data(hexString: "69b2e91be6587307c43c29b027a71fdd55be25f07ca726714115430d23093071")))
		#expect(keys.patchMacKey == (try Data(hexString: "693845bdd996652aca9ca0b96d0f081abf29943303c5eb19bdb84f38b24c32ab")))
	}

	@Test("mixes LTHash values like Baileys")
	func mixesLTHashValuesLikeBaileys() throws {
		let mixer = NativeAppStatePatchHashMixer()
		let first = try mixer.subtractThenAdd(
			hash: Data(repeating: 0, count: 128),
			subtract: [],
			add: [Data("value-v1".utf8)]
		)
		let both = try mixer.subtractThenAdd(
			hash: Data(repeating: 0, count: 128),
			subtract: [],
			add: [Data("value-v1".utf8), Data("value-v2".utf8)]
		)
		let second = try mixer.subtractThenAdd(
			hash: both,
			subtract: [Data("value-v1".utf8)],
			add: []
		)

		#expect(first == (try Data(hexString: "6772983eacaba825169998401f072473dee2d2f75dce1c84f090f3b5ddef61a8a2c40ef9f182c8cde755040c5aed77d6851fe52dd1349e5c0e82c938a0c2c14a2d4f9c484b13eac5e795945e503984c81613ee3cce0b7f400356232556a31adfc96a2288e08d96d0ef1e7e126c22a654bccc2f10bba42b6860b06c792dd35d61")))
		#expect(both == (try Data(hexString: "757d2306693f3ac72e1e3af347e943c7df65ad518bdd807fda106f530085f864298f6959eb110d5e9d0075e33b643867710dce0482bf4c7e3680972760e712bfb128a15710a0c379b204cbf2789037242144f9225f47c426caa2cb44e4bb94c89f1bf57e2767af9448c9c9f76b555151d321ceda4e2da62c835e5d915e96413f")))
		#expect(second == (try Data(hexString: "0e0b8bc7bd9392a11885a2b228e21f540183db592e0f64fbea7f7c9d239597bc87ca5b60fa8e4590b6aa71d7e176c190ecede9d6b18aae2128feceeec024517484d9050fc58cd9b3cb6e37942857b35b0b310be6913b45e6c74ca81f8e187ae9d6b0d3f647d919c459aa4be5ff32abfc17559fca93887bc423aef11731c3e4dd")))
	}

	@Test("rejects invalid LTHash base lengths")
	func rejectsInvalidLTHashBaseLengths() throws {
		#expect(throws: NativeAppStatePatchHashMixerError.invalidHashLength) {
			try NativeAppStatePatchHashMixer().subtractThenAdd(
				hash: Data(repeating: 0, count: 127),
				subtract: [],
				add: [Data("value-v1".utf8)]
			)
		}
	}
}

private extension Data {
	init(hexString: String) throws {
		guard hexString.count.isMultiple(of: 2) else {
			throw HexDataError.invalidLength
		}

		var bytes = [UInt8]()
		bytes.reserveCapacity(hexString.count / 2)
		var index = hexString.startIndex
		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw HexDataError.invalidByte
			}
			bytes.append(byte)
			index = next
		}
		self = Data(bytes)
	}
}

private enum HexDataError: Error {
	case invalidLength
	case invalidByte
}
