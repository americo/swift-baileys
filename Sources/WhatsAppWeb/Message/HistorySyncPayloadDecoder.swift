import Compression
import Foundation

enum HistorySyncPayloadDecoderError: Error, Equatable, Sendable {
	case decompressionFailed
	case compressedPayloadTooLarge
}

enum HistorySyncPayloadDecoder {
	static func decodeCompressed(_ data: Data) throws -> Proto_HistorySync {
		try Proto_HistorySync(serializedBytes: inflateZlib(data))
	}

	static func inflateZlib(_ data: Data) throws -> Data {
		guard !data.isEmpty else {
			throw HistorySyncPayloadDecoderError.decompressionFailed
		}

		var capacity = max(64, data.count * 4)
		let maximumCapacity = 64 * 1024 * 1024

		while capacity <= maximumCapacity {
			var output = Data(count: capacity)
			let decodedCount = output.withUnsafeMutableBytes { outputBuffer in
				data.withUnsafeBytes { inputBuffer in
					compression_decode_buffer(
						outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
						capacity,
						inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
						data.count,
						nil,
						COMPRESSION_ZLIB
					)
				}
			}

			if decodedCount > 0, decodedCount < capacity {
				output.removeSubrange(decodedCount..<output.count)
				return output
			}

			capacity *= 2
		}

		throw HistorySyncPayloadDecoderError.compressedPayloadTooLarge
	}
}
