import Foundation

public struct NoiseFrameCodec: Sendable {
	private let introHeader: Data
	private var sentIntro = false
	private var pendingBytes = Data()

	public init(introHeader: Data = Data()) {
		self.introHeader = introHeader
	}

	public mutating func encode(_ payload: Data) -> Data {
		var frame = Data()

		if !sentIntro {
			frame.append(introHeader)
			sentIntro = true
		}

		frame.append(UInt8((payload.count >> 16) & 0xff))
		frame.append(UInt8((payload.count >> 8) & 0xff))
		frame.append(UInt8(payload.count & 0xff))
		frame.append(payload)
		return frame
	}

	public mutating func decode(_ bytes: Data) -> [Data] {
		pendingBytes.append(bytes)
		var frames: [Data] = []

		while pendingBytes.count >= 3 {
			let size = (Int(pendingBytes[pendingBytes.startIndex]) << 16)
				| (Int(pendingBytes[pendingBytes.index(pendingBytes.startIndex, offsetBy: 1)]) << 8)
				| Int(pendingBytes[pendingBytes.index(pendingBytes.startIndex, offsetBy: 2)])

			guard pendingBytes.count >= size + 3 else {
				break
			}

			let payloadStart = pendingBytes.index(pendingBytes.startIndex, offsetBy: 3)
			let payloadEnd = pendingBytes.index(payloadStart, offsetBy: size)
			frames.append(pendingBytes[payloadStart..<payloadEnd])
			pendingBytes.removeSubrange(pendingBytes.startIndex..<payloadEnd)
		}

		return frames
	}
}
