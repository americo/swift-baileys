enum BusinessPlatformClassifier {
	static func isWhatsAppBusinessPlatform(_ platform: String) -> Bool {
		platform == "smbi" || platform == "smba"
	}
}
