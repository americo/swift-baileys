import Foundation

public enum UnixTimestamp {
	public static func seconds(from date: Date = Date()) -> Int64 {
		Int64(floor(date.timeIntervalSince1970))
	}
}
