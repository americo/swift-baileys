import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Noise frame codec")
struct NoiseFrameCodecTests {
	@Test("prefixes the first encoded frame with the intro header")
	func prefixesFirstEncodedFrameWithIntroHeader() {
		var codec = NoiseFrameCodec(introHeader: Data([0x57, 0x41]))

		let first = codec.encode(Data([1, 2, 3]))
		let second = codec.encode(Data([4, 5]))

		#expect(first == Data([0x57, 0x41, 0, 0, 3, 1, 2, 3]))
		#expect(second == Data([0, 0, 2, 4, 5]))
	}

	@Test("decodes multiple frames from a single buffer")
	func decodesMultipleFramesFromSingleBuffer() {
		var codec = NoiseFrameCodec()

		let frames = codec.decode(Data([0, 0, 2, 1, 2, 0, 0, 3, 3, 4, 5]))

		#expect(frames == [Data([1, 2]), Data([3, 4, 5])])
	}

	@Test("buffers partial frames across decode calls")
	func buffersPartialFramesAcrossDecodeCalls() {
		var codec = NoiseFrameCodec()

		let first = codec.decode(Data([0, 0, 5, 1, 2]))
		let second = codec.decode(Data([3, 4, 5]))

		#expect(first.isEmpty)
		#expect(second == [Data([1, 2, 3, 4, 5])])
	}
}
