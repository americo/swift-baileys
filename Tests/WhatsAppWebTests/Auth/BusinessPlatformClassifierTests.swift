import Testing
@testable import WhatsAppWeb

@Suite("Business platform classifier")
struct BusinessPlatformClassifierTests {
	@Test("recognizes Baileys WhatsApp business platforms")
	func recognizesBaileysWhatsAppBusinessPlatforms() {
		#expect(BusinessPlatformClassifier.isWhatsAppBusinessPlatform("smbi"))
		#expect(BusinessPlatformClassifier.isWhatsAppBusinessPlatform("smba"))
	}

	@Test("rejects non-business platforms")
	func rejectsNonBusinessPlatforms() {
		#expect(!BusinessPlatformClassifier.isWhatsAppBusinessPlatform("macOS"))
		#expect(!BusinessPlatformClassifier.isWhatsAppBusinessPlatform("android"))
		#expect(!BusinessPlatformClassifier.isWhatsAppBusinessPlatform(""))
	}
}
