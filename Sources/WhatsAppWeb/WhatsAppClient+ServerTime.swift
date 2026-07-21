import Foundation

extension WhatsAppClient {
	public func updateServerTimeOffset(_ node: BinaryNode, localDate: Date = Date()) {
		guard let timestamp = node.attrs["t"],
			  let serverTimestampSeconds = Int64(timestamp),
			  serverTimestampSeconds > 0 else {
			return
		}

		let localMilliseconds = Int64(localDate.timeIntervalSince1970 * 1_000)
		serverTimeOffsetMilliseconds = serverTimestampSeconds * 1_000 - localMilliseconds
	}

	public func unixTimestampSeconds(from date: Date = Date()) -> Int64 {
		let adjustedMilliseconds = Int64(date.timeIntervalSince1970 * 1_000) + serverTimeOffsetMilliseconds
		return Int64(floor(Double(adjustedMilliseconds) / 1_000))
	}
}
