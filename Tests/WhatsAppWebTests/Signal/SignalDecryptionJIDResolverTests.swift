import Testing
@testable import WhatsAppWeb

@Suite("Signal decryption JID resolver")
struct SignalDecryptionJIDResolverTests {
	@Test("keeps LID senders unchanged")
	func keepsLIDSendersUnchanged() async throws {
		let resolved = try await SignalDecryptionJIDResolver.resolve(
			senderJID: "123@lid",
			resolveLIDForPN: { _ in "mapped@lid" }
		)

		#expect(resolved == "123@lid")
	}

	@Test("keeps hosted LID senders unchanged")
	func keepsHostedLIDSendersUnchanged() async throws {
		let resolved = try await SignalDecryptionJIDResolver.resolve(
			senderJID: "123@hosted.lid",
			resolveLIDForPN: { _ in "mapped@lid" }
		)

		#expect(resolved == "123@hosted.lid")
	}

	@Test("uses mapped LID for phone-number senders")
	func usesMappedLIDForPhoneNumberSenders() async throws {
		let resolved = try await SignalDecryptionJIDResolver.resolve(
			senderJID: "123@s.whatsapp.net",
			resolveLIDForPN: { jid in
				#expect(jid == "123@s.whatsapp.net")
				return "123@lid"
			}
		)

		#expect(resolved == "123@lid")
	}

	@Test("falls back to the original sender without a mapping")
	func fallsBackToOriginalSenderWithoutMapping() async throws {
		let resolved = try await SignalDecryptionJIDResolver.resolve(
			senderJID: "123@s.whatsapp.net",
			resolveLIDForPN: { _ in nil }
		)

		#expect(resolved == "123@s.whatsapp.net")
	}
}
