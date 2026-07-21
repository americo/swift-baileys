import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Message ID generator")
struct MessageIDGeneratorTests {
	@Test("generates Baileys V2 message ID with user id")
	func generatesBaileysV2MessageIDWithUserID() throws {
		let generator = MessageIDGenerator(
			unixTimestampSeconds: { 1_700_000_000 },
			randomBytes: { count in
				#expect(count == 16)
				return Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
			}
		)

		#expect(try generator.generateV2(userID: "123@s.whatsapp.net") == "3EB075A822D4810DF6AE2D")
	}

	@Test("generated IDs keep the Baileys prefix and length")
	func generatedIDsKeepBaileysPrefixAndLength() throws {
		let id = try MessageIDGenerator().generateV2(userID: "123@s.whatsapp.net")

		#expect(id.hasPrefix("3EB0"))
		#expect(id.count == 22)
	}

	@Test("generates legacy Baileys message ID from random bytes")
	func generatesLegacyBaileysMessageIDFromRandomBytes() throws {
		let generator = MessageIDGenerator(randomBytes: { count in
			#expect(count == 18)
			return Data(0..<18)
		})

		#expect(try generator.generate() == "3EB0000102030405060708090A0B0C0D0E0F1011")
	}

	@Test("legacy generated IDs keep the Baileys prefix and length")
	func legacyGeneratedIDsKeepBaileysPrefixAndLength() throws {
		let id = try MessageIDGenerator().generate()

		#expect(id.hasPrefix("3EB0"))
		#expect(id.count == 40)
	}

	@Test("legacy generator rejects invalid random byte counts")
	func legacyGeneratorRejectsInvalidRandomByteCounts() {
		let generator = MessageIDGenerator(randomBytes: { _ in Data([0x01]) })

		#expect(throws: MessageIDGeneratorError.invalidRandomByteCount) {
			try generator.generate()
		}
	}

	@Test("classifies message id device origins like Baileys")
	func classifiesMessageIDDeviceOriginsLikeBaileys() {
		#expect(MessageIDDeviceClassifier.device(for: "3A123456789012345678") == .iOS)
		#expect(MessageIDDeviceClassifier.device(for: "3EB0123456789012345678") == .web)
		#expect(MessageIDDeviceClassifier.device(for: "123456789012345678901") == .android)
		#expect(MessageIDDeviceClassifier.device(for: "12345678901234567890123456789012") == .android)
		#expect(MessageIDDeviceClassifier.device(for: "3F123") == .desktop)
		#expect(MessageIDDeviceClassifier.device(for: "123456789012345678") == .desktop)
		#expect(MessageIDDeviceClassifier.device(for: "short") == .unknown)
	}

	@Test("generates participant hash V2 like Baileys")
	func generatesParticipantHashV2LikeBaileys() {
		let participants = [
			"258840000003@s.whatsapp.net",
			"258840000001@s.whatsapp.net",
			"258840000002@s.whatsapp.net"
		]

		#expect(ParticipantHashGenerator.generateV2(participants: participants) == "2:Fur4in")
		#expect(ParticipantHashGenerator.generateV2(participants: ["b@s.whatsapp.net", "a@s.whatsapp.net"]) == "2:UELBtg")
		#expect(ParticipantHashGenerator.generateV2(participants: []) == "2:47DEQp")
	}
}
