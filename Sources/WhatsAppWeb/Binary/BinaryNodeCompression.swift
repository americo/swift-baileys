import Foundation
import zlib

enum BinaryNodeCompressionError: Error {
	case inflateFailed
}

enum BinaryNodeCompression {
	static func inflate(_ data: Data) throws -> Data {
		var stream = z_stream()
		let windowBits = MAX_WBITS
		guard inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
			throw BinaryNodeCompressionError.inflateFailed
		}

		defer { inflateEnd(&stream) }

		return try data.withUnsafeBytes { sourceBuffer in
			guard let sourcePointer = sourceBuffer.bindMemory(to: Bytef.self).baseAddress else {
				return Data()
			}

			stream.next_in = UnsafeMutablePointer(mutating: sourcePointer)
			stream.avail_in = uInt(data.count)

			var output = Data()
			var buffer = [UInt8](repeating: 0, count: 16 * 1_024)

			repeat {
				let bufferCount = buffer.count
				let status = buffer.withUnsafeMutableBytes { destinationBuffer in
					stream.next_out = destinationBuffer.bindMemory(to: Bytef.self).baseAddress
					stream.avail_out = uInt(bufferCount)
					return zlib.inflate(&stream, Z_NO_FLUSH)
				}

				guard status == Z_OK || status == Z_STREAM_END else {
					throw BinaryNodeCompressionError.inflateFailed
				}

				output.append(buffer, count: bufferCount - Int(stream.avail_out))

				if status == Z_STREAM_END {
					return output
				}
			} while stream.avail_out == 0 || stream.avail_in > 0

			throw BinaryNodeCompressionError.inflateFailed
		}
	}
}
