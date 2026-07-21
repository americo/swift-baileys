import Foundation

public enum MessageURLExtractor {
	public static func extractURL(from text: String) -> String? {
		let pattern = #"https:\/\/(?![^:@\/\s]+:[^:@\/\s]+@)[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(:\d+)?(\/[^\s]*)?"#
		guard let expression = try? NSRegularExpression(pattern: pattern) else {
			return nil
		}

		let range = NSRange(text.startIndex..<text.endIndex, in: text)
		guard let match = expression.firstMatch(in: text, range: range),
			  let matchRange = Range(match.range, in: text) else {
			return nil
		}

		return String(text[matchRange])
	}
}
